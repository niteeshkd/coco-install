# Setup

You can run the all-in-one setup script `./install.sh` or follow
the individual steps described below.

## Install the OSC operator

```sh
oc apply -f my_catalog.yaml
oc apply -f ns.yaml
oc apply -f og.yaml
oc apply -f subs.yaml
```

You should see controller-manager pods in the `openshift-sandboxed-containers-operator` namespace

```sh
oc get pods -n openshift-sandboxed-containers-operator
```

### Enable Image based deployment

- Enable featuregate

```sh
oc apply -f osc-fg-cm.yaml
```

### Create KataConfig

The example KataConfig deploys Kata on all the worker nodes.
You can use the KataConfigPoolSelector to install Kata only on specific nodes.

```sh
oc apply -f kataconfig.yaml
```

This will start the install and you can watch the progress by observing the
status of the `kata-oc` MachineConfigPool

```sh
oc get mcp
```

After successful install `kata`, `kata-cc-sim`, `kata-cc-tdx` and `kata-cc-snp` runtimeclasses will be created

If you are using a non TEE hardware, then use the `kata-cc-sim` runtimeclass to play with the CoCo workflow

