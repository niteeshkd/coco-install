# Introduction

This describes a way to customise the installed Kata artifacts in OpenShift cluster
to support confidential containers in Azure.


## Prerequisites

1. OpenShift cluster in Azure, installed with the OSC operator
2. KataConfig created with `enablePeerPods: true`

## Setup

Copy the custom shim in the worker nodes with Kata installed
```
kubectl apply -f ds.yaml
```
This will create the daemonset in the `openshift-sandboxed-containers-operator` namespace
and copy the custom shim to `/opt/kata` on all the worker nodes having the label: `node-role.kubernetes.io/kata-oc:`

Create the new MachineConfig to update the Kata configurations

```
kubectl apply -f mc-coco.yaml
```
The MachineConfig will update the CRIO config for the `kata-remote-cc` runtimeClass to point to the custom shim.
Also it will update the Kata configuration-remote.toml


Wait for nodes to be in READY state

```
kubectl get mcp kata-oc --watch
```

## Configure cloud-api-adaptor (CAA)

Patch the `peer-pods-cm` configmap with the following values:

```
 DISABLECVM: "false"
 AZURE_INSTANCE_SIZE: "Standard_DC2as_v5"
 PODVM_IMAGE_ID: "/CommunityGalleries/cococommunity-42d8482d-92cd-415b-b332-7648bd978eff/Images/peerpod-podvm-experimental/Versions/20231010.0.1"
 DISABLE_CLOUD_CONFIG: "true"
```

Patch the CAA deployment to use coco enabled CAA image
```
kubectl set image ds/peerpodconfig-ctrl-caa-daemon -n openshift-sandboxed-containers-operator cc-runtime-install-pod=quay.io/confidential-containers/cloud-api-adaptor:dev-88cfd39a0747f24d6aaf0e3fd92af4c0d4fc5f5a
```

## Deploy KBS

TBD
