# AKS Workload Identity - Sample

`status on this repo = In-Progress`
`app1 = working, app2 = in-progress, app3 = in-progress`

This sample creates an AKS Cluster, and deploys 3 applications which use different AzureAD identities to gain access to secrets in different Azure Key Vaults.

Each application uses a slightly different authentication method;

1. Uses Azure workload identity to access a KeyVault directly from the code in the container
1. Uses the CSI Secrets driver for KeyVault with an Azure workload identity
1. Uses the CSI Secrets driver for KeyVault with an Azure User Assigned Managed Identity

This sample demonstrates the different methods for accessing Key Vaults and the multi-tenancy of application credential stores in AKS.

## Features

This project framework provides the following features:

* AKS Cluster, optimally configured to leverage private link networking and as an OIDC issuer for Workload Identity
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
- 1 AKS Cluster
- 3 Kubernetes namespaces
- 3 Azure Key Vaults
- The Azure Workload Identity Mutating Admission Webhook on the AKS cluster
- A User Assigned Managed Identity for use with Application-3

### Guide

1. clone the repo

```
git clone https://github.com/Azure-Samples/aks-workload-identity.git
cd aks-workload-identity
```

2. Deploy the infrastructure to your azure subscription

```bash
az group create -n akswi -l EastUs
DEP=$(az deployment group create -g akswi -f main.bicep -o json)
OIDCISSUERURL=$(echo $DEP | jq -r '.properties.outputs.aksOidcIssuerUrl.value')
APP1KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp1Name.value')
APP2KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp2Name.value')
APP3KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp3Name.value')

az aks get-credentials -n aks-akswi -g akswi --overwrite-existing
```

4. Create AAD Service Principals (and applications) for app1 and app2

```bash
APP1=$(az ad sp create-for-rbac --name "AksWiApp1" --query "appId" -o tsv)
APP2=$(az ad sp create-for-rbac --name "AksWiApp2"  --query "appId" -o tsv)
```

5. Assign the AAD application permission to access secrets in the correct KeyVault

```bash
APP1SPID="$(az ad sp show --id $APP1 --query id -o tsv)"
az deployment group create -g akswi -f kvRbac.bicep -p kvName=$APP1KVNAME appclientId=$APP1SPID

APP2SPID="$(az ad sp show --id $APP2 --query id -o tsv)"
az deployment group create -g akswi -f kvRbac.bicep -p kvName=$APP2KVNAME appclientId=$APP2SPID
```

6. Deploy the applications

```bash
TENANTID=$(az account show --query tenantId -o tsv)

helm upgrade --install app1 charts/workloadIdApp1 --set azureWorkloadIdentity.tenantId=$TENANTID,azureWorkloadIdentity.clientId=$APP1,keyvaultName=$APP1KVNAME,secretName=arbitarySecret -n app1 --create-namespace

helm upgrade --install app2 charts/workloadIdApp2 --set azureWorkloadIdentity.tenantId=$TENANTID,azureWorkloadIdentity.clientId=$APP2,keyvaultName=$APP2KVNAME,secretName=arbitarySecret -n app2 --create-namespace

helm install charts/workloadIdApp3
```

6b. Checking for errors

We're expecting that both applications that require Federated Id won't be working as we haven't trusted the AKS Cluster from AzureAD.

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
fedReqBody=$(jq -n --arg n "kubernetes-federated-credential-$APP1NAMESPACE-app1" \
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
fedReqBody=$(jq -n --arg n "kubernetes-federated-credential-$APP2NAMESPACE-app2" \
                   --arg i $OIDCISSUERURL \
                   --arg s "system:serviceaccount:$APP2NAMESPACE:$APP2SVCACCNT" \
                   --arg d "Kubernetes service account federated credential" \
             '{name:$n,issuer:$i,subject:$s,description:$d,audiences:["api://AzureADTokenExchange"]}')
echo $fedReqBody | jq -r
az rest --method POST --uri $fedReqUrl --body "$fedReqBody"
```

8. Seeing it working

```bash
APP1POD=$(kubectl get pod -n app1 -o=jsonpath='{.items[0].metadata.name}')
kubectl logs $APP1POD

APP2POD=$(kubectl get pod -n app2 -o=jsonpath='{.items[0].metadata.name}')
kubectl logs $APP2POD
kubectl exec -it $APP2POD -n $app2 -- bash

```

## Resources

- [Azure Workload Identity](https://github.com/Azure/azure-workload-identity)
- [Azure Key Vault provider for Secrets Store CSI Driver](https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/getting-started/usage/)