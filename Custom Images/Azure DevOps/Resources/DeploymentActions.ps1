param (
    [Parameter(HelpMessage = "Remove the existing AIB Object")]
    [switch]    
    $RemoveAIBObject,
    [Parameter(HelpMessage = "The Resource Group Name")]
    [string]
    $ResourceGroupName,
    [Parameter(HelpMessage = "The Image Template Name")]
    [string]
    $imageTemplateName,
    [Parameter(HelpMessage = "Invoke the AIB Build")]
    [switch]
    $InvokeBuild,
    [Parameter(HelpMessage = "Install the required modules")]
    [switch]
    $InstallModules,
    [Parameter(HelpMessage = "The Required PowerShell Modules")]
    [array]
    $ModuleNames = @("Az.ImageBuilder", "Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceManagement.Administration"),
    [Parameter(HelpMessage = "The Windows 365 Provisioning Policy Name")]
    [String]
    $provisioningPolicyDisplayName,
    [Parameter(HelpMessage = "The Azure Image Name")]
    [String]
    $ImageName,
    [Parameter(HelpMessage = "Upload the image to Windows 365")]
    [switch]
    $UploadW365,
    [Parameter(HelpMessage = "Configure the Windows 365 Provisioning Policy")]
    [switch]
    $ConfigureProvisioningPolicy,
    [Parameter(HelpMessage = "The Access Token for Auth")]
    [String]
    $ClientSecret
)

#This section is required as it is currently it is not possible to update an existing AIB image template.
#Instead, the existing object must be removed and a new one created.
IF ($RemoveAIBObject) {
    IF ([System.String]::IsNullOrEmpty($imageTemplateName)) {
        Write-Error "imageTemplateName is required when RemoveAIBObject is specified"
        exit 1
    }
    
    #If a previous image template exists, remove it.
    $currentTemplate = Get-AzImageBuilderTemplate -ResourceGroupName $ResourceGroupName -ImageTemplateName $imageTemplateName -ErrorAction SilentlyContinue
    IF ($null -ne $currentTemplate) {
        Write-Output "Removing AIB Template before creating a new one!"
        $currentTemplate | Remove-AzImageBuilderTemplate
    }
    else {
        Write-Output "No Image Template Detected"
    }
}

IF ($InvokeBuild) {
    $imgTempProperties = Get-AzImageBuilderTemplate -ResourceGroupName $ResourceGroupName -Name $imageTemplateName | Select-Object *
    IF (($imgTempProperties.LastRunStatusRunState -eq "Running") -or ($imgTempProperties.LastRunStatusRunState -eq "InProgress")) {
        Write-Warning "Build already in progress, tracking..."
    }
    else {

        #If the image already exists, remove the image and then create a new one
        $currentAZImage = Get-AzImage -ResourceGroupName $ResourceGroupName -ImageName ($imageTemplateName.Split('-')[0]) -ErrorAction SilentlyContinue
        IF ($null -ne $currentAZImage) {
            Remove-AzImage -ResourceGroupName $ResourceGroupName -ImageName ($imageTemplateName.Split('-')[0]) -Force
        }
        Write-Output "Invoking AIB Build"
        $InvokeJob = Invoke-AzResourceAction -ResourceGroupName $ResourceGroupName -ResourceType Microsoft.VirtualMachineImages/imageTemplates -ResourceName $imageTemplateName -Action Run -Force
        Write-Output "Job Id: $($InvokeJob.Name)"
    }
    Write-Output "Building using Source Image:"
    $imgTempProperties.source
    Write-Output "Building with the following Customisations:"
    $imgTempProperties.customize
    Write-Output "Distributing to:"
    $imgTempProperties.distribute
    $StartTime = Get-Date
    #Check for current deployment state
    DO {
        Start-Sleep 60
        $runState = (Get-AzImageBuilderTemplate -ResourceGroupName $ResourceGroupName -Name $imageTemplateName).LastRunStatusRunState
        Write-Output "Current Build Status: $runState"
    }
    While (($runState -eq "Running") -or ($runState -eq "InProgress")) 
    Write-Output "Build Completed with status: $($runState)"
    Write-Output "Time Taken: $((Get-Date) - $StartTime)"
}

IF ($InstallModules) {
    Write-Output "Installing Modules"
    #For Each Module in the ModuleNames Array, Attempt to install them
    FOREACH ($Module in $ModuleNames) {
        IF (!(Get-Module -ListAvailable -Name $Module)) {
            try {
                Write-Output "Attempting to install $Module Module for the Current Device"
                Install-Module -Name $Module -Force -AllowClobber -ErrorAction SilentlyContinue
            }
            catch {
                Write-Error "Unable to install $Module Module for the Current Device"
            }
        }  
    }
}    

IF ($UploadW365) {
    $SecuredPasswordPassword = ConvertTo-SecureString `
        -String $ClientSecret -AsPlainText -Force
    $ClientSecretCredential = New-Object `
        -TypeName System.Management.Automation.PSCredential `
        -ArgumentList $env:ClientID, $SecuredPasswordPassword
    Connect-AzAccount -ServicePrincipal -Tenant $env:TenantID -Credential $ClientSecretCredential
    $AccessToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
    Connect-MgGraph -AccessToken $AccessToken.Token
    Select-MgProfile -Name "beta"
    Write-Output "Uploading Windows 365 Image"
    $w365Image = Get-AzImage -ResourceGroupName $ResourceGroupName -ImageName $ImageName
    $customImageParams = @{
        DisplayName           = $w365Image.Name
        Version               = (Get-Date -Format "yy.MM.dd")
        SourceImageResourceId = $w365Image.Id
    }
    $w365ImageUpload = New-MgDeviceManagementVirtualEndpointDeviceImage @customImageParams

    #While the image is still uploading, loop to ensure the rest of the script can succeed
    while ((Get-MgDeviceManagementVirtualEndpointDeviceImage -CloudPcDeviceImageId $w365ImageUpload.id).Status -notmatch "ready") {
        "$($w365ImageUpload.DisplayName) upload in-progress"
        Start-Sleep -Seconds 60
    }
}

IF ($ConfigureProvisioningPolicy) {
    #Check if there is a policy with the same name, if so set it to the variable
    $currentProPolicy = Get-MgDeviceManagementVirtualEndpointProvisioningPolicy -Property DisplayName, Id | Where-Object DisplayName -eq $provisioningPolicyDisplayName

    #If the policy exists, update the policy, otherwise create a new provisioning policy. 
    IF ($currentProPolicy) {
        $params = @{
            ImageId          = $w365ImageUpload.id
            ImageDisplayName = $w365ImageUpload.DisplayName
            ImageType        = "custom"
        }
        $provisioningPolicy = Update-MgDeviceManagementVirtualEndpointProvisioningPolicy -CloudPcProvisioningPolicyId $currentProPolicy.id @params
        "$provisioningPolicyDisplayName has been updated"

    }
    ELSE {
        $params = @{
            DisplayName             = $provisioningPolicyDisplayName
            Description             = ""
            ImageId                 = $w365ImageUpload.id
            ImageDisplayName        = $w365ImageUpload.DisplayName
            ImageType               = "custom"
            EnableSingleSignOn      = $true
            MicrosoftManagedDesktop = @{
                Type = "notManaged"
            }
            DomainJoinConfiguration = @{
                Type        = "azureADJoin"
                RegionName  = "automatic"
                RegionGroup = "usWest"
            }
        }
        $provisioningPolicy = New-MgDeviceManagementVirtualEndpointProvisioningPolicy -BodyParameter $params
        "$provisioningPolicyDisplayName ($($provisioningPolicy.id)) has been created"
    }
}