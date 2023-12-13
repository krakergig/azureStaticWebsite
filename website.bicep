@description('Location for all resources.')
param location string = resourceGroup().location

var storageAccountName = '${uniqueString(resourceGroup().id)}azstorage'

@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
@description('The storage account sku name.')
param storageSku string = 'Standard_LRS'

@description('The path to the web index document.')
param indexDocumentPath string = 'index.html'

@description('The contents of the web index document.')
param indexDocumentContents string = '<h1>Example static website</h1>'

@description('The path to the web error document.')
param errorDocument404Path string = 'error.html'

@description('The contents of the web error document.')
param errorDocument404Contents string = '<h1>Example 404 error page</h1>'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

resource contributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  // This is the Storage Account Contributor role, which is the minimum role permission we can give. See https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#:~:text=17d1049b-9a84-46fb-8f53-869881c3d3ab
  name: '17d1049b-9a84-46fb-8f53-869881c3d3ab'
}

// create user assigned managed identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'DeploymentScript'
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: storageAccount
  name: guid(resourceGroup().id, managedIdentity.id, contributorRoleDefinition.id)
  properties: {
    roleDefinitionId: contributorRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'deploymentScript'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  dependsOn: [
    // we need to ensure we wait for the role assignment to be deployed before trying to access the storage account
    roleAssignment
  ]
  properties: {
    azPowerShellVersion: '3.0'
    scriptContent: loadTextContent('./enableStaticWebsite.ps1')
    retentionInterval: 'PT4H'
    environmentVariables: [
      {
        name: 'ResourceGroupName'
        value: resourceGroup().name
      }
      {
        name: 'StorageAccountName'
        value: storageAccount.name
      }
      {
        name: 'IndexDocumentPath'
        value: indexDocumentPath
      }
      {
        name: 'IndexDocumentContents'
        value: indexDocumentContents
      }
      {
        name: 'ErrorDocument404Path'
        value: errorDocument404Path
      }
      {
        name: 'ErrorDocument404Contents'
        value: errorDocument404Contents
      }
    ]
  }
}

output staticWebsiteUrl string = storageAccount.properties.primaryEndpoints.web


@description('The name of the Front Door endpoint to create. This must be globally unique.')
param frontDoorEndpointName string = 'afd-${uniqueString(resourceGroup().id)}'

@description('The name of the SKU to use when creating the Front Door profile.')
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
param frontDoorSkuName string = 'Standard_AzureFrontDoor'


@description('The host name that should be used when connecting to the origin.')
var originHostName = replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')

@description('The path that should be used when connecting to the origin.')
param originPath string = ''

@description('The protocol that should be used when connecting from Front Door to the origin.')
@allowed([
  'HttpOnly'
  'HttpsOnly'
  'MatchRequest'
])
param originForwardingProtocol string = 'HttpsOnly'

@description('If you are using Private Link to connect to the origin, this should specify the resource ID of the Private Link resource (e.g. an App Service application, Azure Storage account, etc). If you are not using Private Link then this should be empty.')
param privateEndpointResourceId string = ''

@description('If you are using Private Link to connect to the origin, this should specify the resource type of the Private Link resource. The allowed value will depend on the specific Private Link resource type you are using. If you are not using Private Link then this should be empty.')
param privateLinkResourceType string = ''

@description('If you are using Private Link to connect to the origin, this should specify the location of the Private Link resource. If you are not using Private Link then this should be empty.')
param privateEndpointLocation string = ''

// When connecting to Private Link origins, we need to assemble the privateLinkOriginDetails object with various pieces of data.
var isPrivateLinkOrigin = (privateEndpointResourceId != '')
var privateLinkOriginDetails = {
  privateLink: {
    id: privateEndpointResourceId
  }
  groupId: (privateLinkResourceType != '') ? privateLinkResourceType : null
  privateLinkLocation: privateEndpointLocation
  requestMessage: 'Please approve this connection.'
}

var profileName = 'MyFrontDoor'
var originGroupName = 'MyOriginGroup'
var originName = 'MyOrigin'
var routeName = 'MyRoute'

resource profile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: profileName
  location: 'global'
  sku: {
    name: frontDoorSkuName
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2021-06-01' = {
  name: frontDoorEndpointName
  parent: profile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2021-06-01' = {
  name: originGroupName
  parent: profile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 100
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2021-06-01' = {
  name: originName
  parent: originGroup
  properties: {
    hostName: originHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: originHostName
    priority: 1
    weight: 1000
    sharedPrivateLinkResource: isPrivateLinkOrigin ? privateLinkOriginDetails : null
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2021-06-01' = {
  name: routeName
  parent: endpoint
  dependsOn: [
    origin // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    originPath: any(originPath != '' ? originPath : null)
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: originForwardingProtocol
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
}

output frontDoorEndpointHostName string = endpoint.properties.hostName
output frontDoorId string = profile.properties.frontDoorId
