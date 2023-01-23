[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]
    $subscription,
    [Parameter(Mandatory = $true)]
    [String]
    $resourceGroupName,
    [Parameter(Mandatory = $true)]
    [String]
    $vNetName,
    [Parameter(Mandatory = $true)]
    [String]
    $subnetName,
    [Parameter(Mandatory = $true)]
    [String]
    $ancName,
    [Parameter(Mandatory = $true)]
    [string]
    $domainOU,
    [Parameter(Mandatory = $true)]
    [string]
    $domainDNSSuffix,
    [Parameter(Mandatory = $true)]
    [string]
    $domainJoinUser,
    [Parameter(Mandatory = $true)]
    [string]
    $domainJoinUserPWD,
    [Parameter(DontShow = $true)]
    [Array]
    $ModuleNames = @("Microsoft.Graph"),
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

$params = @{
	DisplayName = $ancName
	Type = "hybridAzureADJoin"
	SubscriptionId = $subscription
    ResourceGroupId = "/subscriptions/$subscription/resourceGroups/$resourceGroupName"
	VirtualNetworkId = "/subscriptions/$subscription/resourceGroups/$resourceGroupName/providers/Microsoft.Network/virtualNetworks/$vNetName"
	SubnetId = "/subscriptions/$subscription/resourceGroups/$resourceGroupName/providers/Microsoft.Network/virtualNetworks/$vNetName/subnets/$subnetName"
    OrganizationalUnit = $domainOU
	AdDomainName = $domainDNSSuffix
	AdDomainUsername = $domainJoinUser
	AdDomainPassword = $domainJoinUserPWD
}

$ancProfile = New-MgDeviceManagementVirtualEndpointOnPremisesConnection -BodyParameter $params

DO {
    "Azure Network Connection is Being Created"
    Start-Sleep 60
    $policyState = Get-MgDeviceManagementVirtualEndpointOnPremisesConnection -CloudPcOnPremisesConnectionId $ancProfile.Id
}
while ($policyState.HealthCheckStatus -match "running")

Switch ($policyState.HealthCheckStatus) {
    passed {
        "The Azure Network Connection Created Successfully"
    }
    {$PSItem -notmatch "passed"}{
        throw "The Azure Network Connection Creation Failed"
        "Please Review the error state here: https://endpoint.microsoft.com/`#view/Microsoft_Azure_CloudPC/EditAzureConnectionWizardBlade/connectionId/$($policyState.id)/tabIndexToActive~/0"
    }
}