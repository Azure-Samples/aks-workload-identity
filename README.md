# AKS Workload Identity - Sample

`status on this repo = In-Peer-Review`
`app1 = working, app2 = working, app3 = working, app4 = working`

This sample creates an AKS Cluster, and deploys 4 applications which use different AzureAD identities to gain access to secrets in different Azure Key Vaults.

Each application uses a slightly different authentication method;

App # | Identity | Uses CSI Secrets driver | Comments
--- | -------- | ----------------------- | --------
1 | Workload Identity (Service Principal) | :x: | Accesses the KeyVault directly from the code in the container
2 | Workload Identity (Service Principal) | :heavy_check_mark: |
3 | User Assigned Managed Identity | :heavy_check_mark: | 
4 | Managed Identity | :heavy_check_mark: | Leverages the AKS managed azureKeyvaultSecretsProvider identity

These samples demonstrate the different methods for accessing Key Vaults and the *multi-tenancy of application credential stores* in AKS.

## Features

This project framework provides the following features:

* AKS Cluster, configured as an OIDC issuer for Workload Identity with the CSI Secrets driver installed
* Azure Key Vault, for application secret storage
* Azure Workload Identity, for application access to the Key Vaults

### Diagram

## Getting Started

### Prerequisites

Interaction with Azure is done using the [Azure CLI](https://docs.microsoft.com/cli/azure/), [Helm](https://helm.sh/docs/intro/install/) and [Kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) are required for accessing Kubernetes packages and installing them to the cluster.

[JQ](https://stedolan.github.io/jq/download/) is used for transforming json objects in the script samples. It's a commonly used binary available in the Azure CLI, on GitHub runners etc.

OIDC Issuer is a Preview AKS Feature, and [should be enabled](https://docs.microsoft.com/azure/aks/cluster-configuration#oidc-issuer-preview) on your subscription.

### Installation

#### AKS

Using [AKS Construction](https://github.com/Azure/Aks-Construction), we can quickly set up an AKS cluster to the correct configuration. It has been referenced as a git submodule, and therefore easily consumed in [this projects bicep infrastructure file](main.bicep).

The main.bicep deployment creates
- 1 AKS Cluster, with CSI Secrets Managed Identity
- 4 Kubernetes namespaces
- 4 Azure Key Vaults
- The Azure Workload Identity Mutating Admission Webhook on the AKS cluster

### Guide

1. clone the repo

```
git clone https://github.com/Azure-Samples/aks-workload-identity.git
cd aks-workload-identity
```

2. Deploy the infrastructure to your azure subscription

```bash
RGNAME=akswi
az group create -n $RGNAME -l EastUs
DEP=$(az deployment group create -g $RGNAME -f main.bicep -o json)
OIDCISSUERURL=$(echo $DEP | jq -r '.properties.outputs.aksOidcIssuerUrl.value')
AKSCLUSTER=$(echo $DEP | jq -r '.properties.outputs.aksClusterName.value')
APP1KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp1Name.value')
APP2KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp2Name.value')
APP3KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp3Name.value')
APP4KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp4Name.value')
APP3=$(echo $DEP | jq -r '.properties.outputs.idApp3ClientId.value')

az aks get-credentials -n $AKSCLUSTER -g $RGNAME --overwrite-existing
```

4. Create AAD Service Principals (and applications) for app1 and app2

```bash
APP1=$(az ad sp create-for-rbac --name "AksWiApp1" --query "appId" -o tsv)
APP2=$(az ad sp create-for-rbac --name "AksWiApp2" --query "appId" -o tsv)
```

5. AAD application permissions 

We need to allow both of the Service Principals for APP1 and APP2 to access secrets in the correct KeyVault. APP3's Managed Identity was already granted RBAC during the bicep infrastructure creation.

```bash
APP1SPID="$(az ad sp show --id $APP1 --query id -o tsv)"
az deployment group create -g $RGNAME -f kvRbac.bicep -p kvName=$APP1KVNAME appclientId=$APP1SPID

APP2SPID="$(az ad sp show --id $APP2 --query id -o tsv)"
az deployment group create -g $RGNAME -f kvRbac.bicep -p kvName=$APP2KVNAME appclientId=$APP2SPID

#App4
CSICLIENTID=$(az aks show -g $RGNAME --name $AKSCLUSTER --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
CSIOBJECTID=$(az aks show -g $RGNAME --name $AKSCLUSTER --query addonProfiles.azureKeyvaultSecretsProvider.identity.objectId -o tsv)
az deployment group create -g $RGNAME -f kvRbac.bicep -p kvName=$APP4KVNAME appclientId=$CSIOBJECTID
```

6. Deploy the applications

```bash
TENANTID=$(az account show --query tenantId -o tsv)

helm upgrade --install app1 charts/workloadIdApp1 --set azureWorkloadIdentity.tenantId=$TENANTID,azureWorkloadIdentity.clientId=$APP1,keyvaultName=$APP1KVNAME,secretName=arbitarySecret -n app1 --create-namespace

helm upgrade --install app2 charts/workloadIdApp2 --set azureWorkloadIdentity.tenantId=$TENANTID,azureWorkloadIdentity.clientId=$APP2,keyvaultName=$APP2KVNAME,secretName=arbitarySecret -n app2 --create-namespace

helm upgrade --install app3 charts/csiApp --set azureKVIdentity.tenantId=$TENANTID,azureKVIdentity.clientId=$APP3,keyvaultName=$APP3KVNAME,secretName=arbitarySecret -n app3 --create-namespace

helm upgrade --install app4 charts/csiApp --set azureKVIdentity.tenantId=$TENANTID,azureKVIdentity.clientId=$CSICLIENTID,keyvaultName=$APP4KVNAME,secretName=arbitarySecret -n app4 --create-namespace
```

6b. Checking for errors

We're expecting that both applications that require Federated Id won't be working as we haven't trusted the AKS Cluster from AzureAD. At this point it should just be Application 4 working as it's identity configuration is the simplest.

These errors however are useful to see what is expected to be provided when we created the Federated Identity.

```bash
APP1POD=$(kubectl get pod -n app1 -o=jsonpath='{.items[0].metadata.name}')
kubectl logs $APP1POD -n app1
```

> error: AADSTS70021: No matching federated identity record found for presented assertion. Assertion Issuer: 'https://oidc.prod-aks.azure.com/REDACTED/'. Assertion Subject: 'system:serviceaccount:default:app2-workloadidapp'. Assertion Audience: 'api://AzureADTokenExchange'.

7. Establish federated identity credentials for the workload identities

App1 

```bash
APP1SVCACCNT="app1-workloadidapp1"
APP1NAMESPACE="app1"
APP1APPOBJECTID="$(az ad app show --id $APP1 --query id -o tsv)"

#Create federated identity credentials for use from an AKS Cluster Service Account
fedReqUrl="https://graph.microsoft.com/beta/applications/$APP1APPOBJECTID/federatedIdentityCredentials"
fedReqBody=$(jq -n --arg n "kubernetes-$AKSCLUSTER-$APP1NAMESPACE-app1" \
                   --arg i $OIDCISSUERURL \
                   --arg s "system:serviceaccount:$APP1NAMESPACE:$APP1SVCACCNT" \
                   --arg d "Kubernetes service account federated credential" \
             '{name:$n,issuer:$i,subject:$s,description:$d,audiences:["api://AzureADTokenExchange"]}')
echo $fedReqBody | jq -r
az rest --method POST --uri $fedReqUrl --body "$fedReqBody"
```

App2

```bash 
APP2SVCACCNT="app2-workloadidapp2"
APP2NAMESPACE="app2"
APP2APPOBJECTID="$(az ad app show --id $APP2 --query id -o tsv)"

#Create federated identity credentials for use from an AKS Cluster Service Account
fedReqUrl="https://graph.microsoft.com/beta/applications/$APP2APPOBJECTID/federatedIdentityCredentials"
fedReqBody=$(jq -n --arg n "kubernetes-$AKSCLUSTER-$APP2NAMESPACE-app2" \
                   --arg i $OIDCISSUERURL \
                   --arg s "system:serviceaccount:$APP2NAMESPACE:$APP2SVCACCNT" \
                   --arg d "Kubernetes service account federated credential" \
             '{name:$n,issuer:$i,subject:$s,description:$d,audiences:["api://AzureADTokenExchange"]}')
echo $fedReqBody | jq -r
az rest --method POST --uri $fedReqUrl --body "$fedReqBody"
```

8. Assigning Managed Identity to the VMSS

The last step in getting App3 working is to assign the User Assigned Managed Identity to the Virtual Machine Scaleset used by the AKS User nodepool.

```bash
NODEPOOLNAME=$(echo $DEP | jq -r '.properties.outputs.aksUserNodePoolName.value')
RGNODE=$(echo $DEP | jq -r '.properties.outputs.nodeResourceGroup.value')
APP3RESID=$(echo $DEP | jq -r '.properties.outputs.idApp3Id.value')
VMSSNAME=$(az vmss list -g $RGNODE --query "[?tags.\"aks-managed-poolName\" == '$NODEPOOLNAME'].name" -o tsv)
az vmss identity assign -g $RGNODE -n $VMSSNAME --identities $APP3RESID
```

9. Seeing all the apps working

These scripts show the pod successfully accessing the secret in the respective application Key Vaults.

```bash
APP1POD=$(kubectl get pod -n app1 -o=jsonpath='{.items[0].metadata.name}')
kubectl logs $APP1POD -n app1

APP2POD=$(kubectl get pod -n app2 -o=jsonpath='{.items[0].metadata.name}')
kubectl exec -it $APP2POD -n app2 -- cat /mnt/secrets-store/arbitarySecret

APP3POD=$(kubectl get pod -n app3 -o=jsonpath='{.items[0].metadata.name}')
kubectl exec -it $APP3POD -n app3 -- cat /mnt/secrets-store/arbitarySecret

APP4POD=$(kubectl get pod -n app4 -o=jsonpath='{.items[0].metadata.name}')
kubectl exec -it $APP4POD -n app4 -- cat /mnt/secrets-store/arbitarySecret
```

## Resources

- [Azure Workload Identity](https://github.com/Azure/azure-workload-identity)
- [Azure Key Vault provider for Secrets Store CSI Driver](https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/getting-started/usage/)