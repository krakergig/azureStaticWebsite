@description('Specifies the location for resources.')
param location string = 'westeurope'

targetScope = 'subscription'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'testResourceGroup'
  location: location
}

module function './function.bicep' = {
  name: 'FunctionDeployment'
  scope: resourceGroup 
  params: {
    appInsightsLocation: location
    location: location
    runtime: 'node'
    appName: 'fnapp${uniqueString(resourceGroup.id)}'
    storageAccountType: 'Standard_LRS'
  }
}

module storage './website.bicep' = {
  name: 'WebsiteDeployment'
  scope: resourceGroup 
  params: {
    location: location
    storageSku: 'Standard_LRS'
  }
}
