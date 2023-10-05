# Install

## Prerequisites
OpenShift cluster installed with OSC operator and KataConfig created

## Setup CoCo using upstream bits

Apply the machineconfig

```
kubectl apply -f mc.yaml
```

Wait for nodes to be in READY state

```
kubectl get mcp kata-oc --watch
```

Apply the daemonset manifest to copy kata shim to the worker node

```
kubectl apply -f ds.yaml
```

Create the runtimeclass
```
kubectl apply -f runtimeclass-coco.yaml
```
