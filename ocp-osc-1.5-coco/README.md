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

```sh
kubectl apply -f mc-coco.yaml
```
The MachineConfig will update the CRIO config for the `kata-cc-tdx`, `kata-cc-snp`, `kata-cc-sev`
and `kata-cc-sim` runtimeClasses.

Wait for nodes to be in READY state

```sh
kubectl get mcp kata-oc --watch
```

## Create RuntimeClass


Use the manifest depending on your setup.
For TDX:
```sh
kubectl apply -f rc-kata-cc-tdx.yaml
```

For SNP:
```sh
kubectl apply -f rc-kata-cc-snp.yaml
```

For SEV:
```sh
kubectl apply -f rc-kata-cc-sev.yaml
```

For non-CC hardware:
```sh
kubectl apply -f rc-kata-cc-sim.yaml
```

The `kata-cc-sim` runtimeClass is to try out the CoCo stack on a non-CC hardware.


# Deploy a test workload

Use the example manifest depending on your setup.
Example on non-CC hardware use this:

```sh
kubectl apply -f test-cc-sim.yaml
```

If not using a CC hardware then, use the correct manifest
based on the CC hardware - sev, snp or tdx.
Example:
```sh
kubectl apply -f test-cc-tdx.yaml
```
