# AKS Workload Identity - Sample

`status on this repo = In-Progress`

This sample creates an AKS Cluster, and deploys 2 applications which leverage workload identity to gain access to secrets in keyvault.

## Features

This project framework provides the following features:

* AKS Cluster, optimally configured to leverage private link networking and as an OIDC issuer for Workload Identity
* Key vaults, configured to be access securely
* Workload Identity, via 2 sample applications deployed to the cluster

## Getting Started

### Prerequisites

Interaction with Azure is done using the [Azure CLI](https://docs.microsoft.com/cli/azure/), [Helm](https://helm.sh/docs/intro/install/) and [Kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) are required for accessing Kubernetes packages and installing them to the cluster.

### Installation

#### AKS

Using [AKS Construction](https://github.com/Azure/Aks-Construction), we can quickly set up an AKS cluster in a virtual network.

```bash
az group create -n akswi -l EastUs
az deployment group create -g akswi -u https://github.com/Azure/AKS-Construction/releases/download/0.8.2/main.json -p resourceName=akswi oidcIssuer=true
az aks get-credentials -n akswi -g akswi --overwrite-existing
```


### Quickstart
(Add steps to get up and running quickly)

1. git clone [repository clone url]
2. cd [repository name]
3. ...


## Demo

A demo app is included to show how to use the project.

To run the demo, follow these steps:

(Add steps to start up the demo)

1.
2.
3.

## Resources

(Any additional resources or related projects)

- Link to supporting information
- Link to similar sample
- ...
