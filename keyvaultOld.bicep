//This bicep code has been extracted from AKSConstruction main.bicep
//It'll be refactored out soon to make it more easily referencable... but here it is for the moment

@minLength(2)
@description('The location to use for the deployment. defaults to Resource Groups location.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(20)
@description('Used to name all resources')
param resourceName string

@description('Enable support for private links')
param privateLinks bool = false

@description('If soft delete protection is enabled')
param KeyVaultSoftDelete bool = true

@description('If purge protection is enabled')
param KeyVaultPurgeProtection bool = true

@description('Add IP to KV firewall allow-list')
param kvIPAllowlist array = []

var akvRawName = 'kv-${replace(resourceName, '-', '')}${uniqueString(resourceGroup().id, resourceName)}'
var akvName = length(akvRawName) > 24 ? substring(akvRawName, 0, 24) : akvRawName

var kvIPRules = [for kvIp in kvIPAllowlist: {
  value: kvIp
}]

resource kv 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: akvName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    // publicNetworkAccess:  whether the vault will accept traffic from public internet. If set to 'disabled' all traffic except private endpoint traffic and that that originates from trusted services will be blocked.
    publicNetworkAccess: privateLinks && empty(kvIPAllowlist) ? 'disabled' : 'enabled'

    networkAcls: privateLinks && !empty(kvIPAllowlist) ? {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: kvIPRules
      virtualNetworkRules: []
    } : {}

    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: KeyVaultSoftDelete
    enablePurgeProtection: KeyVaultPurgeProtection ? true : json('null')
  }
}
output keyvaultName string = kv.name
