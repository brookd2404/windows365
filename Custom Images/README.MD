# Create the Azure Infrastructure for AIB

Before we get started creating the Azure Image Builder Template, we need to create the underlying azure resources that will then feed into the creation process. 

## Prerequsites 

- **Owner** permissions on the Subscription. 

## Executing the script

The **Create-AIBInfrastructure.ps1** script will first of all register the required components for Image Builder, Documentation can be found on this [LINK](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-powershell#register-features). Following on from that it will create a resource group to separate out the resources, followed by the creating of a User Managed Identity and a custom role for this identity which will be scoped at the resource group. 

Let start by  gather 

| Property         | Example | Description |
|--------------    |--------------------------------------|-----------|
| SubscriptionID  |  b493a1f9-4895-45fe-bb71-152b36eea469 | The ID of the Azure Subscription where the resources will be created. |
| geoLocation | UKSouth | The Azure region in which resources will be provisioned|
| aibRG| W365-CI-EUC365 | The name of the resource group to be created |

Once you have all of the above, execute the script like the following example.

`Create-AIBInfrastructure.ps1 -SubscriptionID "b493a1f9-4895-45fe-bb71-152b36eea469" -geoLocation "UKSouth" -aibRG "W365-CI-EUC365" -imageRoleDefName "w365CustomImage"`

</br>
<hr> 

# Create the AIB Image

## Image Options

One of the first things we need to obtain is the Image Offer we will use as out base template. To do so, follow the below steps;

1. Obtain the [Get-ImageOptions](https://github.com/brookd2404/Powershell_Scripts/blob/master/Azure/Get-ImageOptions.ps1) script
2. Run this script, specifying your Subscription ID, Geo Locations (e.g UKSouth, EastUS etc.) and the Image Publisher (which for this case is MicrosoftWindowsDesktop). </br></br> `Get-ImageOptions.ps1 -SubscriptionId <Subid> -geoLocation "UKSouth" -imagePublisher "MicrosoftWindowsDesktop"` </br>

3. Locate the **windows-ent-cpc** heading, and take note of an image offer. 

For those wondering, this denotes **Windows Enterprise Cloud PC**. There are two options for later versions of the OS, which are M365 or OS. To help make your decision, please review the [**Cloud PC Device images overview**](https://learn.microsoft.com/en-us/windows-365/enterprise/device-images#gallery-images) documentation.

