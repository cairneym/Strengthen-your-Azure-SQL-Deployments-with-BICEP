param storageRoleMapping object
param roleName string
param indexValue int
param associatedResourceName string
param deployLocation string = resourceGroup().location
param identityName string



resource newStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: '${indexValue}storage${uniqueString(resourceGroup().id, associatedResourceName)}'
  location: deployLocation
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource addRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name : guid('${indexValue}${uniqueString(resourceGroup().id, associatedResourceName, roleName)}')
  scope : newStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefintitions', storageRoleMapping[roleName])
    principalId: reference(resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', identityName), '2018-11-30', 'Full').properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output blobEndpoint string = newStorage.properties.primaryEndpoints.blob
output storageId string = newStorage.id 

