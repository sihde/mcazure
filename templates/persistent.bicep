param projectName string {
  metadata: {
    description: 'description'
  }
  default: 'hamachi-mc'
}
param adminId string {
  metadata: {
    description: 'GUID of vault owner principal'
  }
}

var location = 'westus2'
var tenantId = subscription().tenantId
var idName = '${projectName}-id'
var diskName = 'minecraft-datadisk1'
var vaultName = '${projectName}-vault'
var storageAccountName = 'hamachifiles'
var fileShareName = '${projectName}-share'

var rolePrefix = '${subscription().id}/providers/Microsoft.Authorization/roleDefinitions/'
var roleReader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var roleReaderAndDataAccess = 'c12c1c16-33a1-487b-954d-41c89c60f349'
var roleKeyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
var roleKeyVaultAdministrator = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

resource msi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: idName
  location: location
}

resource idReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(subscription().id, msi.id, roleReader)
  properties: {
    description: 'MSI needs Reader access to itself for az login to work on VM'
    roleDefinitionId: '${rolePrefix}${roleReader}'
    principalId: reference(msi.name).principalId
  }
  scope: msi
}

resource storageReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(subscription().id, msi.id, storageAccount.id, roleReaderAndDataAccess)
  properties: {
    roleDefinitionId: '${rolePrefix}${roleReaderAndDataAccess}'
    principalId: reference(msi.name).principalId
  }
  scope: storageAccount
}

resource vault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
  }
}

resource keyVaultUserRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(subscription().id, msi.id, vault.id, roleKeyVaultSecretsUser)
  properties: {
    roleDefinitionId: '${rolePrefix}${roleKeyVaultSecretsUser}'
    principalId: reference(msi.name).principalId
  }
  scope: vault
}

resource keyVaultAdminRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(subscription().id, adminId, vault.id, roleKeyVaultAdministrator)
  properties: {
    roleDefinitionId: '${rolePrefix}${roleKeyVaultAdministrator}'
    principalId: adminId
  }
  scope: vault
}

resource disk 'Microsoft.Compute/disks@2020-06-30' = {
  name: diskName
  location: location
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Upload'
    }
    diskSizeGB: 16
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_ZRS'
    tier: 'Standard'
  }
  properties: {
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2019-06-01' = {
  name: '${storageAccountName}/default/${fileShareName}'
  properties: {
    accessTier: 'TransactionOptimized'
    enabledProtocols: 'SMB'
  }
  dependsOn: [
    storageAccount
  ]
}