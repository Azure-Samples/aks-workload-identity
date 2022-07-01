# AKS Workload Identity - Sample

`status on this repo = In-Progress`

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
DEP=$(az deployment group create -g akswi -f main.bicep)
OIDCISSUERURL=$(echo $DEP | jq -r '.properties.outputs.aksOidcIssuerUrl.value')
APP1KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp1Name.value')
APP2KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp2Name.value')
APP3KVNAME=$(echo $DEP | jq -r '.properties.outputs.kvApp3Name.value')

az aks get-credentials -n aks-akswi -g akswi --overwrite-existing
```

4. Create AAD applications for app1 and app2

```bash
APP1=$(az ad sp create-for-rbac --name "AksWiApp1")
APP1CLIENTID=$APP1

APP2=$(az ad sp create-for-rbac --name "AksWiApp2")
APP2CLIENTID=$APP2
```

5. Assign the AAD application permission to access secrets in the correct KeyVault

```bash
az deployment group create -g akswi -f kvRbac.bicep -p kvName=kv-app1akswi app1clientId=$APP1CLIENTID
az deployment group create -g akswi -f kvRbac.bicep -p kvName=kv-app2akswi app1clientId=$APP2CLIENTID
```

6. Deploy the applications

```bash
TENANTID=$(az account show --query tenantId -o tsv)
helm install charts/workloadIdApp1 --set azureWorkloadIdentity.tenantId=$TENANTID,azureWorkloadIdentity.clientId=$APP1CLIENTID
helm install charts/workloadIdApp2 --set azureWorkloadIdentity.tenantId=$TENANTID,azureWorkloadIdentity.clientId=$APP2CLIENTID
helm install charts/workloadIdApp3
```

7. Establish federated identity credentials for the workload identities

```bash
APPOBJECTID="$(az ad app show --id ${APPCLIENTID} --query id -otsv)"
```

## Resources

- [Azure Workload Identity](https://github.com/Azure/azure-workload-identity)
- [Azure Key Vault provider for Secrets Store CSI Driver](https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/getting-started/usage/)