# Introduction

This describes a way to customise the installed Kata artifacts in OpenShift cluster
for experimenting with GPU instances in cloud.


## Prerequisites

1. OpenShift cluster in AWS or Azure, installed with the OSC operator
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
kubectl apply -f mc-gpu.yaml
```
The MachineConfig will update the CRIO config for the `kata-remote-cc` runtimeClass to point to the custom shim.
Also it will update the Kata configuration-remote.toml


Wait for nodes to be in READY state

```
kubectl get mcp kata-oc --watch
```
