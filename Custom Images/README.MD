# Create the Azure Infrastructure for AIB

Before we get started creating the Azure Image Builder Template, we need to create the underlying azure resources that will then feed into the creation process. 

## Prerequisites  

- **Owner** permissions on the Subscription. 

## Executing the script

The **Create-AIBInfrastructure.ps1** script will first of all register the required components for Image Builder, Documentation can be found on this [LINK](https://learn.microsoft.com/en-us/azure/virtual-machines/windows/image-builder-powershell#register-features). Following on from that it will create a resource group to separate out the resources, followed by the creating of a User Managed Identity and a custom role for this identity which will be scoped at the resource group. 

Let start by gathering the data in the following table; 

| Property         | Example | Description |
|--------------    |--------------------------------------|-----------|
| SubscriptionID  |  b493a1f9-4895-45fe-bb71-152b36eea469 | The ID of the Azure Subscription where the resources will be created. |
| geoLocation | UKSouth | The Azure region in which resources will be provisioned|
| aibRG| W365-CI-EUC365 | The name of the resource group to be created |

Once you have all of the above, execute the script like the following example.

`Create-AIBInfrastructure.ps1 -SubscriptionID "b493a1f9-4895-45fe-bb71-152b36eea469" -geoLocation "UKSouth" -aibRG "W365-CI-EUC365" -imageRoleDefName "w365CustomImage"`

</br>
<hr> 

# Create the AIB Image and Update Provisioning Policy

Although throughout this process, we are creating an Azure Image Builder Template, we can not natively use this with Windows 365 Cloud PC's for deployment. At the end of the process, the script will create a Managed Disk that is then uploaded into the Windows 365 service. 

The **Create-Windows365AIB.ps1** script will handle this work for you, and when passed in a name for a Windows 365 Provisioning policy, it will also go ahead and update that. If you provide a name, and it does not exist. The script will create the policy. 

## Prerequisites 
- **Intune Administrator** Permissions (Delegated)
- **CloudPC.ReadWrite.All** Permissions (Application)
- **Contributor** Rights to the Resource Group

## Image Options

One of the first things we need to obtain is the Image Offer we will use as out base template. To do so, follow the below steps;

1. Obtain the [Get-ImageOptions](https://github.com/brookd2404/Powershell_Scripts/blob/master/Azure/Get-ImageOptions.ps1) script
2. Run this script, specifying your Subscription ID, Geo Locations (e.g UKSouth, EastUS etc.) and the Image Publisher (which for this case is MicrosoftWindowsDesktop). </br></br> `Get-ImageOptions.ps1 -SubscriptionId <Subid> -geoLocation "UKSouth" -imagePublisher "MicrosoftWindowsDesktop"` </br>

3. Locate the **windows-ent-cpc** heading, and take note of an image offer. 

For those wondering, this denotes **Windows Enterprise Cloud PC**. There are two options for later versions of the OS, which are M365 or OS. To help make your decision, please review the [**Cloud PC Device images overview**](https://learn.microsoft.com/en-us/windows-365/enterprise/device-images#gallery-images) documentation.

## Image Customisations

As you will see in the script, there are three customisations, two 'Inline' and 1 script URI. Now these are the bits that make your images do the business, there is a bit of trial and error some times, but when you find your groove, it becomes like shelling peas. 

If you search for `$ImgCustomParams` this will locate the customisations. If you add, or remove one, please do not forget to update the `$ImgTemplateParams` object!

## Executing the Script

Let start by gathering the data in the following table, some of which will be the same values used earlier in the process.

| Property         | Example | Description |
|--------------    |--------------------------------------|-----------|
| SubscriptionID  |  b493a1f9-4895-45fe-bb71-152b36eea469 | The ID of the Azure Subscription where the resources will be created. |
| geoLocation | UKSouth | The Azure region in which resources will be provisioned|
| aibRG| W365-CI-EUC365 | The name of the resource group to be created |
|imageTemplateName | w365-vs-template | The name of the Image Template to Create
|aibGalleryName | igw365 | The name of the Image Gallery to create/update </br> NOTE; You cannot use special characters or spaces in this field.
|imageDefinitionName | w365Images | The name of the image definition to create
|galleryPublisherName | MyCompany | The publisher display name of the custom image.
|provisioningPolicyDisplayName | W365 - Visual Studio Community 2022 | The name of your Windows 365 Provisioning Policy.
|publisher | MicrosoftWindowsDesktop | (Optional) This value is set by default, but please do update to suit your needs, please see the **Image Option** section above
|offerName | windows-ent-cpc | (Optional) This value is set by default, but please do update to suit your needs, please see the **Image Option** section above
|offerSku | win11-22h2-ent-cpc-m365 | (Optional) This value is set by default, but please do update to suit your needs, please see the **Image Option** section above
|runOutputName | w365DistResult | (Optional)

<hr>
</br>
The easiest way to call the script it by using an Object to specify your values and then call the script as below;

```
$Params = @{
    subscriptionID = "b493a1f9-4895-45fe-bb71-152b36eea469"
    geoLocation = "uksouth"
    aibRG = "W365-CI-EUC365"
    imageTemplateName = "w365-vs-template"
    aibGalleryName = 'elabcigw365'
    imageDefinitionName = 'w365Images'
    provisioningPolicyDisplayName = "PSDayUK 2023 Demo"
    publisher = "MicrosoftWindowsDesktop"
    offerName = "windows-ent-cpc"
    offerSku = "win11-22h2-ent-cpc-m365"
    runOutputName = "w365DistResult" 
}

& '.\Create-Windows365AIB.ps1' @Params
```

# Conclusion

You now have the basics to make a success of your deployment, make it what you need it to be, please do not hesitate to fork the repo and suggest changes!! 

## Troubleshooting Resources

- [Microsoft Documentation](https://learn.microsoft.com/en-gb/azure/virtual-machines/linux/image-builder-troubleshoot)