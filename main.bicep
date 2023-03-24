param sqlServerName string = 'arm-template-example'
param deployLocation string = 'australiaeast'
param managedIdentity string = 'sqlDBMI'
param sqlAdminSID string = '45e01165-f442-46c8-ab08-35dd99ebd95a'
@secure()
param secretValue string 


var subscriptionId = subscription().subscriptionId
var resourceGroupName = resourceGroup().name
var keyVaultName = format('kv{0}', uniqueString(resourceGroup().id))
var keyVaultRoleIdMapping = {
      'Key Vault Administrator': '00482a5a-887f-4fb3-b363-3b7fe8e74483'
      'Key Vault Certificates Officer': 'a4417e6f-fecd-4de8-b567-7b0420556985'
      'Key Vault Crypto Officer': '14b46e9e-c2b7-41b4-b07b-48a6ebf60603'
      'Key Vault Crypto Service Encryption User': 'e147488a-f6f5-4113-8e2d-b22465e65bf6'
      'Key Vault Crypto User': '12338af0-0e69-4776-bea7-57ae8d297424'
      'Key Vault Reader': '21090545-7ca7-4776-b22c-e363652d74d2'
      'Key Vault Secrets Officer': 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
      'Key Vault Secrets User': '4633458b-17de-408a-b874-0445c86b69e6'
}
var storageRoleMapping = {
      'Storage Blob Data Contributor': 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}
var myTags = {
      event: 'Make Stuff Go'
      version : 'initial'
}


resource userMI 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
      name: managedIdentity
      location: deployLocation
      tags: myTags
}

resource sqlSvr 'Microsoft.Sql/servers@2022-05-01-preview' = {
      name: sqlServerName
      location: deployLocation
      tags: myTags
      identity: {
            type: 'UserAssigned'
            userAssignedIdentities: {
                  '${userMI.id}' : {}
            }
      }
      properties: {
            version: '12.0'
            minimalTlsVersion: '1.2'
            publicNetworkAccess: 'Enabled'
            administrators: {
                  administratorType: 'ActiveDirectory'
                  azureADOnlyAuthentication: true
                  login: 'SQLAdmins'
                  principalType: 'Group'
                  sid: sqlAdminSID
                  tenantId: subscription().tenantId
            }
            primaryUserAssignedIdentityId: userMI.id
      }
}

resource AdventureWorksLT 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
      name: 'AdventureWorksLT'
      parent: sqlSvr
      location: deployLocation
      tags: myTags
      sku: {
            name: 'Basic'
            tier: 'Basic'
      }
      properties: {
            collation: 'SQL_Latin1_General_CP1_CI_AS'
            sampleName: 'AdventureWorksLT'
            zoneRedundant: false
      }
}

resource AllowAllAzureIps 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
      name: 'AllowAllAzureIps'
      parent: sqlSvr
      properties: {
            startIpAddress: '0.0.0.0'
            endIpAddress: '0.0.0.0'
      }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
      name: keyVaultName
      location: deployLocation
      tags: myTags
      properties: {
            enableRbacAuthorization: true
            tenantId: subscription().tenantId
            sku: {
                  name: 'standard'
                  family: 'A'
            }
            networkAcls: {
                  defaultAction: 'Allow'
                  bypass: 'AzureServices'
            }
            enableSoftDelete: false
      }
      resource keyVaultName_TestSecret 'secrets@2021-04-01-preview' = {
            name: 'TestSecret'
            properties: {
                  value: secretValue
            }
      }
}

// resource keyVaultName_TestSecret 'Microsoft.KeyVault/vaults/secrets@2021-04-01-preview' = {
//       name: 'TestSecret'
//       parent: keyVault
//       properties: {
//             value: secretValue
//       }
// }

resource keyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
      name: guid(keyVaultRoleIdMapping['Key Vault Administrator'], managedIdentity, keyVault.id)
      scope: keyVault
      properties: {
            roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefintitions', keyVaultRoleIdMapping['Key Vault Administrator'])
            principalId: userMI.properties.principalId
            principalType: 'ServicePrincipal'
      }
}

module sa 'storage.bicep' = [for i in range(0, 2): {
      name : format('{0}storageDeploy', i)
      params: {
            associatedResourceName: sqlServerName
            identityName: managedIdentity
            deployLocation: deployLocation
            storageRoleMapping: storageRoleMapping
            roleName: 'Storage Blob Data Contributor'
            indexValue: i
      }
      dependsOn: [
            userMI
      ]
}]

resource sqlDefaultAuditingSettings 'Microsoft.Sql/servers/auditingSettings@2022-02-01-preview' = {
      name: 'default'
      parent: sqlSvr
      properties: {
            storageEndpoint: sa[0].outputs.blobEndpoint
            isDevopsAuditEnabled: false
            isManagedIdentityInUse: true
            retentionDays: 1
            state: 'Enabled'
      }
}

resource sqlDiagSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
      name: 'LogToStorage'
      scope : AdventureWorksLT
      properties: {
            storageAccountId: sa[1].outputs.storageId
            logs: [
                    {
                        category: 'SQLInsights'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'AutomaticTuning'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }

                    {
                        category: 'QueryStoreRuntimeStatistics'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'QueryStoreWaitStatistics'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'Errors'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'DatabaseWaitStatistics'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'Timeouts'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'Blocks'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }
                    {
                        category: 'Deadlocks'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                    }       
            ]
            metrics: [
                  {
                        category: 'Basic'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                        timeGrain : 'PT1M'
                    }
                    {
                        category: 'InstanceAndAppAdvanced'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                        timeGrain : 'PT1M'
                    }
                    {
                        category: 'WorkloadManagement'
                        enabled: true
                        retentionPolicy: {
                            days: 1
                            enabled: true
                        }
                        timeGrain : 'PT1M'
                    }
            ]
      }
}

output auditStorageEndpoint string = sa[0].outputs.blobEndpoint
output auditStorageName string = format('{0}storage{1}', 0, uniqueString(resourceGroup().id, sqlServerName))
output sqlUserAssignedID string = sqlSvr.properties.primaryUserAssignedIdentityId


// To deploy, run the following from a terminal
// az login
// az account set --subscription '8a7f048c-6f0d-4cd2-82c2-f1d8495ef39c'
// az deployment group create --resource-group BICEP --template-file main.bicep --parameters main.parameters.json
// az bicep upgrade
