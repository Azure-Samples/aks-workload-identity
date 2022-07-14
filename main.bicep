param nameseed string = 'akswi'
param location string =  resourceGroup().location

@description('This parameter controls the level of network controls configured on the Azure Key Vault')
param networkLockedDown bool = true

//---------Kubernetes Construction---------
module aksconst 'aks-construction/bicep/main.bicep' = {
  name: 'aksconstruction'
  params: {
    location : location
    resourceName: nameseed
    enable_aad: true
    enableAzureRBAC : true
    registries_sku: 'Premium'
    omsagent: true
    retentionInDays: 30
    agentCount: 3
    
    //Workload Identity requires OidcIssuer to be configured on AKS
    oidcIssuer: true
    
    //We'll also enable the CSI driver for Key Vault
    azureKeyvaultSecretsProvider: true
  }
}
output aksOidcIssuerUrl string = aksconst.outputs.aksOidcIssuerUrl
output aksClusterName string = aksconst.outputs.aksClusterName

module kvapp1 'keyvault.bicep' = {
  name: 'kvapp1${nameseed}'
  params: {
    resourceName: 'app1${nameseed}'
    KeyVaultPurgeProtection: false
    KeyVaultSoftDelete: false
    kvIPAllowlist: []
    location: location
    privateLinks: false
  }
}
output kvApp1Name string = kvapp1.outputs.keyvaultName

module kvapp2 'keyvault.bicep' = {
  name: 'kvapp2${nameseed}'
  params: {
    resourceName: 'app2${nameseed}'
    KeyVaultPurgeProtection: false
    KeyVaultSoftDelete: false
    kvIPAllowlist: []
    location: location
    privateLinks: false
  }
}
output kvApp2Name string = kvapp2.outputs.keyvaultName

module kvapp3 'keyvault.bicep' = {
  name: 'kvapp3${nameseed}'
  params: {
    resourceName: 'app3${nameseed}'
    KeyVaultPurgeProtection: false
    KeyVaultSoftDelete: false
    kvIPAllowlist: []
    location: location
    privateLinks: false
  }
}
output kvApp3Name string = kvapp3.outputs.keyvaultName

module kvapp4 'keyvault.bicep' = {
  name: 'kvapp4${nameseed}'
  params: {
    resourceName: 'app4${nameseed}'
    KeyVaultPurgeProtection: false
    KeyVaultSoftDelete: false
    kvIPAllowlist: []
    location: location
    privateLinks: false
  }
}
output kvApp4Name string = kvapp4.outputs.keyvaultName

resource app3id 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'id-app3'
  location: location
}
output idApp3ClientId string = app3id.properties.clientId
output idApp3Id string = app3id.id

module kvApp3Rbac 'kvRbac.bicep' = {
  name: 'App3KvRbac'
  params: {
    appclientId: app3id.properties.principalId
    kvName: kvapp3.outputs.keyvaultName
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2022-05-02-preview' existing = {
  name: aksconst.outputs.aksClusterName
}

module aadWorkloadId 'workloadId.bicep' = {
  name: 'aadWorkloadId-helm'
  params: {
    aksName: aksconst.outputs.aksClusterName
    location: location
  }
}

output aksUserNodePoolName string = 'npuser01' //hardcoding this for the moment.
output nodeResourceGroup string = 'mc_${resourceGroup().name}_aks-${resourceGroup().name}_${location}' //hardcoding this for the moment.
