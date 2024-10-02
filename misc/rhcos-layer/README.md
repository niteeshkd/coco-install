# Creating RHCOS Layer

## With access to OCP cluster

This project contains artifacts to create RHCOS image layer for TDX and SNP.
It requires access to an OCP cluster to know the base RHCOS version to use.

Build for tdx

```sh
make TEE=tdx build
```

Build for snp

```sh
make TEE=snp build
```

## Without access to OCP cluster

You can also directly build using podman or docker.

- Download the OCP pull secret from console.redhat.com
- Run the following command:

This uses RHCOS base image for OCP 4.16

Build for tdx

```sh
podman build --authfile /tmp/pull-secret.json \
   --build-arg OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:31feb7503f06db4023350e3d9bb3cfda661cc81ff21cef429770fb12ae878636 \
   -t tdx-image -f tdx/Containerfile .
```

Build for snp

```sh
podman build --authfile /tmp/pull-secret.json \
   --build-arg OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:31feb7503f06db4023350e3d9bb3cfda661cc81ff21cef429770fb12ae878636 \
   -t snp-image -f snp/Containerfile .
```
