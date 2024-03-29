<#
.SYNOPSIS
    Creates an Azure Image Builder Template, converts it to a managed disk and uploads it to Windows 365 before Updating the provisioning policy. 
.DESCRIPTION
    Creates an Azure Image Builder Template, converts it to a managed disk and uploads it to Windows 365 before Updating the provisioning policy. 

    With the use of Customiser objects it makes it easy to stand up a custom Windows 365 Image in very little time. 
.EXAMPLE
    $Params = @{
        subscriptionID = "b493a1f9-4895-45fe-bb71-152b36eea469"
        geoLocation = "uksouth"
        aibRG = "W365-CI-EUC365"
        imageTemplateName = "w365-vs-template"
        aibGalleryName = 'elabcigw365'
        imageDefinitionName = 'w365Images'
        provisioningPolicyDisplayName = "W365 Demo"
        publisher = "MicrosoftWindowsDesktop"
        offerName = "windows-ent-cpc"
        offerSku = "win11-22h2-ent-cpc-m365"
        runOutputName = "w365DistResult" 
        galleryPublisherName = "MyCompany"
    }

    & '.\Create-Windows365AIB.ps1' @Params
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    $subscriptionID,
    [Parameter(Mandatory = $true)]
    [String]
    $geoLocation,
    [Parameter(Mandatory = $true)]
    [String]
    $aibRG,
    [Parameter(Mandatory = $true)]
    [String]
    $imageTemplateName,
    [Parameter(Mandatory = $true)]
    [string]
    $aibGalleryName,
    [Parameter(Mandatory = $true)]
    [string]
    $imageDefinitionName,
    [Parameter(Mandatory = $true)]
    [String]
    $provisioningPolicyDisplayName,
    [Parameter(Mandatory = $true)]
    [string]
    $galleryPublisherName,
    [string]
    $publisher = "MicrosoftWindowsDesktop",
    [String]
    $offerName = "windows-ent-cpc",
    [string]
    $offerSku = "win11-22h2-ent-cpc-m365",
    [String]
    $runOutputName = "w365DistResult",
    [Parameter(DontShow = $true)]
    [String]
    $identityName = "$aibRG-UMI",
    [Parameter(DontShow = $true)]
    [Array]
    $ModuleNames = @("Az.Compute", "Az.ImageBuilder", "Az.Resources", "Microsoft.Graph"),
    [Parameter(DontShow = $true)]
    [array]
    $Scopes = @("CloudPC.ReadWrite.All")
)

#For Each Module in the ModuleNames Array, Attempt to install them
FOREACH ($Module in $ModuleNames) {
    IF (!(Get-Module -ListAvailable -Name $Module)) {
        try {
            Write-Output "Attempting to install $Module Module for the Current Device"
            Install-Module -Name $Module -Force -AllowClobber
        }
        catch {
            Write-Output "Attempting to install $Module Module for the Current User"
            Install-Module -Name $Module -Force -AllowClobber -Scope CurrentUser
        }
    }  
}


#Connect to Azure and Microsoft Graph
Connect-MgGraph -Scopes $Scopes
Select-MgProfile -Name beta
Connect-AzAccount

#Check if the current context is the right Subscription
IF ((-Not((Get-AzContext).Subscription.id -match $subscriptionID))) {
    #Set Azure Subscription Context
    Set-AzContext -SubscriptionId$subscriptionID
}

#Create an Azure Image Gallery
IF (-Not(Get-AZGallery -GalleryName $aibGalleryName -ResourceGroupName $aibRG -ErrorAction SilentlyContinue)) {
    New-AzGallery -GalleryName $aibGalleryName -ResourceGroupName $aibRG -Location $geoLocation
}

#Create a gallery definition
$GalleryParams = @{
    GalleryName       = $aibGalleryName
    ResourceGroupName = $aibRG
    Location          = $geoLocation
    Name              = $imageDefinitionName
    OsState           = 'generalized'
    OsType            = 'Windows'
    Publisher         = $galleryPublisherName
    Offer             = 'Windows'
    Sku               = 'CPC'
    HyperVGeneration  = "V2"
}
New-AzGalleryImageDefinition @GalleryParams

#Create an Image
$SrcObjParams = @{
    PlatformImageSource = $true
    Publisher           = $publisher
    Offer               = $offerName
    Sku                 = $offerSku
    Version             = 'latest'

}
$srcPlatform = New-AzImageBuilderTemplateSourceObject @SrcObjParams

#Create a VM Image Builder distributor object
$disObjParams = @{
    SharedImageDistributor = $true
    ArtifactTag            = @{tag = 'dis-share' }
    GalleryImageId         = "/subscriptions/$subscriptionID/resourceGroups/$aibRG/providers/Microsoft.Compute/galleries/$aibGalleryName/images/$imageDefinitionName"
    ReplicationRegion      = $geoLocation
    RunOutputName          = $runOutputName
    ExcludeFromLatest      = $false
}
$disSharedImg = New-AzImageBuilderTemplateDistributorObject @disObjParams

#Add Image Customisations (Apps, Directories etc.)
$ImgCustomParams01 = @{
    PowerShellCustomizer = $true
    Name                 = 'settingUpMgmtAgtPath'
    RunElevated          = $true
    RunAsSystem          = $true
    Inline               = @("mkdir c:\\buildActions", "mkdir c:\\buildArtifacts", "echo Azure-Image-Builder-Was-Here  > c:\\buildActions\\buildActionsOutput.txt")
}
$Customizer01 = New-AzImageBuilderTemplateCustomizerObject @ImgCustomParams01
  
$ImgCustomParams02 = @{
    PowerShellCustomizer = $true
    Name                 = 'ChromeInstall'
    RunElevated          = $true
    RunAsSystem          = $true
    scripturi            = "https://raw.githubusercontent.com/brookd2404/Powershell_Scripts/master/appInstalls/Chrome.ps1"
}
$Customizer02 = New-AzImageBuilderTemplateCustomizerObject @ImgCustomParams02


$ImgCustomParams03 = @{
    PowerShellCustomizer = $true
    Name                 = 'vsInstall'
    RunElevated          = $true
    RunAsSystem          = $true
    Inline               = @('$uri = "https://aka.ms/vs/17/release/vs_community.exe" 
$tempFile = "$env:Temp\vsInstall.exe"
$installArgs = "--add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Workload.Python;includeRecommended --quiet"

$webCli = New-Object System.Net.WebClient;
$webCli.DownloadFile($uri, $tempFile)

Start-Process -FilePath $tempFile -ArgumentList $installArgs -Wait'
    )
}
$Customizer03 = New-AzImageBuilderTemplateCustomizerObject @ImgCustomParams03

#If a previous image template exists, remove it.
IF (Get-AzImageBuilderTemplate -ResourceGroupName $aibRG -ImageTemplateName $imageTemplateName -ErrorAction SilentlyContinue) {
    "Removing AIB Template before creating a new one!"
    Get-AzImageBuilderTemplate -ResourceGroupName $aibRG -ImageTemplateName $imageTemplateName | Remove-AzImageBuilderTemplate
}

## Get the User Managed Identity ID
$identityNameResourceId = (Get-AzUserAssignedIdentity -ResourceGroupName $aibRG -Name $identityName).Id

#Create AIB Template
$ImgTemplateParams = @{
    ImageTemplateName      = $imageTemplateName
    ResourceGroupName      = $aibRG
    Source                 = $srcPlatform
    Distribute             = $disSharedImg
    Customize              = $Customizer01, $Customizer02, $Customizer03
    Location               = $geoLocation
    UserAssignedIdentityId = $identityNameResourceId
}
New-AzImageBuilderTemplate @ImgTemplateParams | Out-Null
"AIB Template Created"

#Start the Image Building
Start-AzImageBuilderTemplate -ResourceGroupName $aibRG -Name $imageTemplateName -AsJob
#While the image is Running or In Progress, wait for 60 seconds and then check again.
DO {
    "Still Processing AIB Image"
    Start-Sleep 60
    $runState = (Get-AzImageBuilderTemplate -ResourceGroupName $aibRG -Name $imageTemplateName).LastRunStatusRunState
}
While (($runState -eq "Running") -or ($runState -eq "InProgress")) 



###### Convert AIB To Managed Disk, and then to and Image for Windows 365 #######

#Get the latest version of the image from the Gallery
$latestImgVer = (Get-AzGalleryImageVersion `
        -GalleryImageDefinitionName $imageDefinitionName `
        -GalleryName $aibGalleryName `
        -ResourceGroupName $aibRG `
    | Sort-Object -Descending -Property Name 
)[0]
 
#Create the Managed Disk Configuration 
$diskConfig = New-AzDiskConfig `
    -Location $geoLocation `
    -CreateOption FromImage `
    -GalleryImageReference @{Id = $latestImgVer.Id } `
    -HyperVGeneration V2

#Give the disk a name 
$managedDiskName = "w365OSDisk$($latestImgVer.Name)"

#If the disk exists, remove the disk
IF (Get-AzDisk -ResourceGroupName $aibRG -DiskName $managedDiskName -ErrorAction SilentlyContinue) {
    Remove-AzDisk -ResourceGroupName $aibRG -DiskName $managedDiskName -Force
}
#Create the Managed Disk based on the configuration defined
$managedDisk = New-AzDisk -Disk $diskConfig `
    -ResourceGroupName $aibRG `
    -DiskName $managedDiskName

#Create the OS Managed Disk to be uploaded to Windows 365
$imageConfig = New-AzImageConfig -Location $geoLocation -HyperVGeneration V2
$imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Windows -ManagedDiskId $managedDisk.ID

$outputImageName = "Windows365Image-$($latestImgVer.Name)"

#If the image already exists, remove the image and then create a new one
IF (Get-AzImage -ResourceGroupName $aibRG -ImageName $outputImageName -ErrorAction SilentlyContinue) {
    Remove-AzImage -ResourceGroupName $aibRG -ImageName $outputImageName -Force
}
$imageOutput = New-AzImage -ImageName $outputImageName -ResourceGroupName $aibRG -Image $imageConfig 

#Create upload the created managed disk to Windows 365 using the Graph PowerShell Module
$customImageParams = @{
    DisplayName           = $imageOutput.Name
    Version               = $latestImgVer.Name
    SourceImageResourceId = $imageOutput.Id
}
$w365ImageUpload = New-MgDeviceManagementVirtualEndpointDeviceImage @customImageParams

#While the image is still uploading, loop to ensure the rest of the script can succeed
while ((Get-MgDeviceManagementVirtualEndpointDeviceImage -CloudPcDeviceImageId $w365ImageUpload.id).Status -notmatch "ready") {
    "$($w365ImageUpload.DisplayName) upload is still in-progress"
    Start-Sleep -Seconds 60
}

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