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
  For example if you want to install the pre-GA 1.7.0-11 build, then change the
  image entry to the following

  ```sh
  image: quay.io/openshift_sandboxed_containers/openshift-sandboxed-containers-operator-catalog:1.7.0-11
  ```

  Ensure that the catalog version exists in the registry.
  Also ensure that the `startingCSV` attribute in `subs.yaml` aligns with the CSV in the catalog

- The pre-GA build images are in an authenticated registry, so you'll need to
  set the `PULL_SECRET_JSON` variable with the registry credentials. Following is an example:

  ```sh
  set +o history
  REGISTRY_USER="REPLACE_ME"
  REGISTRY_PASSWORD="REPLACE_ME"

  # Combine credentials and encode in base64
  REGISTRY_AUTH_B64=$(echo -n "${REGISTRY_USER}:${REGISTRY_PASSWORD}" | base64)

  # Create the JSON string using the encoded credentials
  export PULL_SECRET_JSON=$(cat <<EOF
  {
    "brew.registry.redhat.io": {"auth": "${REGISTRY_AUTH_B64}"},
    "registry.redhat.io": {"auth": "${REGISTRY_AUTH_B64}"}
  }
EOF
  )
  set -o history

  ```

- Kickstart the installation by running the following:

  ```sh
  ./install.sh -m -s -b
  ```

  This will deploy ARO and install the pre-GA release of OSC operator.
