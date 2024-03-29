<#
.SYNOPSIS
    This script is intended to create the required Azure Image Builder Infrastructure.
.DESCRIPTION
    This script is intended to create the required Azure Image Builder Infrastructure.

    This script will install all of the required modules, register the required providers on the Subscription, create a resource group, create a user managed identity and a custom role for the identity. 
.NOTES
    You must have Owner Permissions on your Azure Subscription to carry out the execution of this. 
.EXAMPLE
    Create-AIBInfrastructure.ps1 -SubscriptionID "b493a1f9-4895-45fe-bb71-152b36eea469" -geoLocation "UKSouth" -aibRG "W365-CI-EUC365" -imageRoleDefName "w365CustomImage"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]
    $subscriptionID,
    [Parameter(Mandatory = $true)]
    [String]
    $geoLocation,
    [Parameter(Mandatory = $true)]
    [String]
    $aibRG,
    [Parameter(DontShow = $true)]
    [String]
    $imageRoleDefName = "Azure Image Builder Image Definition for $aibRG",
    [Parameter(DontShow = $true)]
    [String]
    $identityName = "$aibRG-UMI",
    [Parameter(DontShow = $true)]
    [Array]
    $ModuleNames = @("Az.Accounts", "Az.Resources", "Az.ManagedServiceIdentity")
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

#Connect to Azure
Connect-AzAccount 

#Check if the current context is the right Subscription
IF ((-Not((Get-AzContext).Subscription.id -match $subscriptionID))) {
    #Set Azure Subscription Context
    Set-AzContext -SubscriptionId $subscription
}

#Register AIB Features if not registered (https://learn.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-powershell#register-features)
Get-AzResourceProvider -ProviderNamespace Microsoft.Compute, 
                                        Microsoft.KeyVault, 
                                        Microsoft.Storage, 
                                        Microsoft.VirtualMachineImages, 
                                        Microsoft.Network | 
            Where-Object RegistrationState -ne Registered | 
            Register-AzResourceProvider

#If the resource group does not exist, create one
IF (-Not(Get-AzResourceGroup -name $aibRG -ErrorAction SilentlyContinue)) {
    #Create a Resource Group with the name specified and in the region specified 
    New-AzResourceGroup -Name $aibRG -Location $geoLocation  
}

#region Create the AIB User Identity and set Role Permissions
IF (-Not(Get-AzUserAssignedIdentity -ResourceGroupName $aibRG -Name $identityName -SubscriptionId $subscriptionID -ErrorAction SilentlyContinue)) {
    New-AzUserAssignedIdentity -ResourceGroupName $aibRG -Name $identityName -Location $geoLocation
    $identityNamePrincipalId = (Get-AzUserAssignedIdentity -ResourceGroupName $aibRG -Name $identityName).PrincipalId
    "User Managed Identity Created: $identityName"
}

IF (-Not(Get-AzRoleDefinition -Name $imageRoleDefName -ErrorAction SilentlyContinue)) {
    $ScopeDefinition = @{
        "Name"             = $imageRoleDefName
        "IsCustom"         = $true
        "Description"      = "Image Builder access to create resources for the image build, you should delete or split out as appropriate"
        "Actions"          = @(
            "Microsoft.Compute/galleries/read",
            "Microsoft.Compute/galleries/images/read",
            "Microsoft.Compute/galleries/images/versions/read",
            "Microsoft.Compute/galleries/images/versions/write",
            "Microsoft.Compute/images/write",
            "Microsoft.Compute/images/read",
            "Microsoft.Compute/images/delete",
            "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action"
        )
        "AssignableScopes" = @(
            "/subscriptions/$subscriptionID/resourceGroups/$aibRG"
        )
    }

    #Create the role definition
    New-AzRoleDefinition -Role $ScopeDefinition
    "Azure Role Definition Created: $imageRoleDefName"
}

#While the identity does not have the role assigned, try assign it. 
while (-not(Get-AzRoleAssignment -RoleDefinitionName $imageRoleDefName -ObjectId $identityNamePrincipalId -Scope "/subscriptions/$subscriptionID/resourceGroups/$aibRG" -ErrorAction SilentlyContinue)) {
    "Assigning Role Assignment to $identityName"
    #Grant the role definition to the AIB Service Principal
    $RoleAssignParams = @{
        ObjectId           = $identityNamePrincipalId
        RoleDefinitionName = $imageRoleDefName
        Scope              = "/subscriptions/$subscriptionID/resourceGroups/$aibRG"
    }
    New-AzRoleAssignment @RoleAssignParams -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10 #Wait 10 seconds before trying again
}
#endregion Create the AIB User Identity and set Role Permissions

