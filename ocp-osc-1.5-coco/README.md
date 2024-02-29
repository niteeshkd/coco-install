# Introduction

This describes a way to customise the installed Kata artifacts in OpenShift cluster
to support confidential containers on baremetal using Qemu


## Prerequisites

1. OpenShift cluster with at least 1 bare metal worker node, installed with the OSC operator (>=1.5.x)
2. KataConfig created

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
The MachineConfig will update the CRIO config for the `kata-cc-tdx`, `kata-cc-snp` and `kata-cc-sim` runtimeClass

Wait for nodes to be in READY state

```
kubectl get mcp kata-oc --watch
```

## Create RuntimeClass


Use the manifest depending on your setup.
For TDX:
```
kubectl apply -f rc-kata-cc-tdx.yaml
```

For SNP:
```
kubectl apply -f rc-kata-cc-snp.yaml

```
For non-CC hardware:
```
kubectl apply -f rc-kata-cc-sim.yaml
```

The `kata-cc-sim` runtimeClass is to try out the CoCo stack on a non-CC hardware.

# Deploy a test workload

Use the example manifest depending on your setup.
Example on non-CC hardware use this:

```
kubectl apply -f test-cc-sim.yaml
```

If not using a CC hardware then, use the correct manifest
based on the CC hardware - snp or tdx.
Example:
```
kubectl apply -f test-cc-tdx.yaml
```
