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
    agentCount: 2
    
    //Workload Identity requires OidcIssuer to be configured on AKS
    oidcIssuer: true
    
    //We'll also enable the CSI driver for Key Vault
    azureKeyvaultSecretsProvider: true
  }
}
output aksOidcIssuerUrl string = aksconst.outputs.aksOidcIssuerUrl

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
