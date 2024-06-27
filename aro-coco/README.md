# Setup

## Install OSC GA release

- Update `startingCSV` key in the `subs-ga.yaml` file to use the GA release you need.

- Kickstart the installation by running the following:

  ```sh
  ./install.sh
  ```

  This will deploy ARO and install the OSC operator.

## Install OSC pre-GA release

- Update osc_catalog.yaml to point to the pre-GA catalog
  For example if you want to install the pre-GA 1.6.0-57 build, then change the
  image entry to the following

  ```sh
  image: quay.io/openshift_sandboxed_containers/openshift-sandboxed-containers-operator-catalog:1.6.0-57
  ```

- The pre-GA build images are in an authenticated registry, so you'll need to
  set the `PULL_SECRET_JSON` variable with the registry credentials. Following is an example:

  ```sh
  export PULL_SECRET_JSON='{"brew.registry.redhat.io": {"auth": "abcd1234"}, "registry.redhat.io": {"auth": "abcd1234"}}'
  ```

- Kickstart the installation by running the following:

  ```sh
  ./install.sh -m -s -b
  ```

  This will deploy ARO and install the pre-GA release of OSC operator.
