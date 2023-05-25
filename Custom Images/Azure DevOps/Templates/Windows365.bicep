param location string = resourceGroup().location
param imageTemplateName string
param ImageOffer string
param ImageSKU string
param AIBVMSize string
param AIBMSIName string
param OSDiskSize int
param BuildTimeout int

var ImageDefName = imageTemplateName
var aibObjName = '${imageTemplateName}-imgTemplate'

resource aibObj 'Microsoft.VirtualMachineImages/imageTemplates@2021-10-01' = {
  name: aibObjName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', AIBMSIName)}': {}
    }
  }
  properties: {
    buildTimeoutInMinutes: BuildTimeout
    vmProfile: {
      vmSize: AIBVMSize
      osDiskSizeGB: OSDiskSize
      userAssignedIdentities: [
        resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', AIBMSIName)
      ]
    }
    source: {
      type: 'PlatformImage'
      publisher: 'MicrosoftWindowsDesktop'
      offer: ImageOffer
      sku: ImageSKU
      version: 'latest'
    }
    customize: [
      {
        type: 'PowerShell'
        runElevated: true
        runAsSystem: true
        name: 'InstallChrome'
        scriptUri: 'https://raw.githubusercontent.com/brookd2404/Powershell_Scripts/master/appInstalls/Chrome.ps1'
      }
    ]
    distribute: [
      {
        type: 'ManagedImage'
        imageId: resourceId('Microsoft.Compute/images', ImageDefName) 
        location: location
        runOutputName: 'MI-${ImageDefName}'
      }
    ]
  }
}

output ImageTemplateName string = ImageDefName
