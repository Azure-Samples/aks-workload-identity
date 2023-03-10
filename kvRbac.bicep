param kvName string
param appclientId string

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: kvName
}

var keyVaultSecretsUserRole = resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
resource kvAppGwSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, appclientId, keyVaultSecretsUserRole)
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole
    principalType: 'ServicePrincipal'
    principalId: appclientId
  }
}

resource arbitrarySecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: kv
  name: 'arbitrarySecret'
  properties: {
    value: 'Squirrel-${guid(kv.id)}'
  }
}
