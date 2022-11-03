param nameseed string = 'akswi'
param location string =  resourceGroup().location

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
    keyVaultAksCSI : true
  }
}
output aksOidcIssuerUrl string = aksconst.outputs.aksOidcIssuerUrl
output aksClusterName string = aksconst.outputs.aksClusterName

module keyVaults 'aks-construction/bicep/keyvault.bicep' = [ for i in range(1,5) : {
  name: 'kvapp${i}${nameseed}'
  params: {
    resourceName: 'app${i}${nameseed}'
    keyVaultPurgeProtection: false
    keyVaultSoftDelete: false
    location: location
    privateLinks: false
  }
}]
output kvApp1Name string = keyVaults[0].outputs.keyVaultName
output kvApp2Name string = keyVaults[1].outputs.keyVaultName
output kvApp3Name string = keyVaults[2].outputs.keyVaultName
output kvApp4Name string = keyVaults[3].outputs.keyVaultName
output kvApp5Name string = keyVaults[4].outputs.keyVaultName

resource app1id 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'id-app1'
  location: location
  
  resource fedCreds 'federatedIdentityCredentials' = {
    name: '${nameseed}-app1'
    properties: {
      audiences: aksconst.outputs.aksOidcFedIdentityProperties.audiences
      issuer: aksconst.outputs.aksOidcFedIdentityProperties.issuer
      subject: 'system:serviceaccount:app1:app1-workloadidapp1'
    } //aksconst.outputs.aksOidcFedIdentityProperties
  }
}
output idApp1ClientId string = app1id.properties.clientId
output idApp1Id string = app1id.id

module kvApp1Rbac 'kvRbac.bicep' = {
  name: 'App1KvRbac'
  params: {
    appclientId: app1id.properties.principalId
    kvName: keyVaults[0].outputs.keyVaultName
  }
}

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
    kvName: keyVaults[2].outputs.keyVaultName
  }
}

resource app5id 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'id-app5'
  location: location
}
output idApp5ClientId string = app3id.properties.clientId
output idApp5Id string = app3id.id

module kvApp5Rbac 'kvRbac.bicep' = {
  name: 'App5KvRbac'
  params: {
    appclientId: app5id.properties.principalId
    kvName: keyVaults[4].outputs.keyVaultName
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

output aksUserNodePoolName string = 'npuser01' //[for nodepool in aks.properties.agentPoolProfiles: name] // 'npuser01' //hardcoding this for the moment.
output nodeResourceGroup string = aksconst.outputs.aksNodeResourceGroup
