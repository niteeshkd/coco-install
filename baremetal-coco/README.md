# Introduction

These are helper scripts to setup CoCo on a bare-metal OpenShift worker node.

NodeFeatureDiscovery (NFD) operator is used to label the TDX and SNP nodes.
`intel.feature.node.kubernetes.io/tdx: "true"` is used for TDX nodes and
`amd.feature.node.kubernetes.io/snp: "true"` is used for SNP nodes.

Kata runtime is configured on the nodes with the above labels.
Note that currently the script only supports installing a single TEE environment.

## Install OSC GA release

- Update `startingCSV` key in the `subs-ga.yaml` file to use the GA release you need.

- Kickstart the installation by running the following:

  For TDX hosts:

  ```sh
  ./install.sh -t tdx
  ```

  For SNP hosts:

  ```sh
  ./install.sh -t snp
  ```

  This will install the OSC operator and configure Kata with CoCo support on the bare-metal worker node.

## Install OSC pre-GA release

- Update osc_catalog.yaml to point to the pre-GA catalog
  For example if you want to install the pre-GA 0.0.1-24 build, then change the
  image entry to the following

  ```sh
  image: quay.io/openshift_sandboxed_containers/openshift-sandboxed-containers-operator-catalog:0.0.1-22
  ```

- The pre-GA build images are in an authenticated registry, so you'll need to
  set the `PULL_SECRET_JSON` variable with the registry credentials. Following is an example:

  ```sh
  export PULL_SECRET_JSON='{"brew.registry.redhat.io": {"auth": "abcd1234"}, "registry.redhat.io": {"auth": "abcd1234"}}'
  ```

- Kickstart the installation by running the following:

  ```sh
  ./install.sh -t tdx -m -s -b
  ```

  This will deploy the pre-GA release of OSC operator on TDX hosts.

After successful install `kata`, `kata-tdx` or `kata-snp` runtimeclasses will be created
