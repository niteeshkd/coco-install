# Setup

Run the all-in-one setup script `./install.sh` to deploy ARO
and install OSC operator.

When using early test builds of the operator, then run the script
with `-m` option. This will create image mirroring configuration

If the operator images are in an authenticated registry, then you'll need to
update the OCP cluster-wide image pull secret by following these steps

```sh
export PULL_SECRET_JSON='{"my.registry.io": {"auth": "ABC"}}'
./install.sh -s
```

## Install the OSC operator

```sh
oc apply -f image_mirroring.yaml
oc apply -f osc_catalog.yaml
oc apply -f ns.yaml
oc apply -f og.yaml
oc apply -f subs.yaml
```

You should see controller-manager pods in the `openshift-sandboxed-containers-operator` namespace

```sh
oc get pods -n openshift-sandboxed-containers-operator
```

## Create peer-pods-cm and peer-pods-secret objects

## Create kataconfig

```sh
oc apply -f kataconfig.yaml
```
