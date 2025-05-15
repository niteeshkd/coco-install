# Creating RHCOS Layer

## With access to OCP cluster

This project contains artifacts to create RHCOS image layer for TDX and SNP.
It requires access to an OCP cluster to know the base RHCOS version to use.

Build for tdx

```sh
make TEE=tdx build
```

To add the CA certs file (say ca-certs) and Registry auth file (say config.json) to the initrd,
run the following.
```sh
sudo make TEE=tdx CA_CERTS=ca-certs REG_AUTH=config.json build
```

Build for snp

```sh
sudo make TEE=snp build
```

To add the CA certs file (say ca-certs) and Registry auth file (say config.json) to the initrd,
run the following.
```sh
sudo make TEE=snp CA_CERTS=ca-certs REG_AUTH=config.json build
```

## Without access to OCP cluster

You can also directly build using podman or docker.

- Download the OCP pull secret from console.redhat.com
- Run the following command:

This uses RHCOS base image for OCP 4.18

Build for tdx

```sh
podman build --authfile /tmp/pull-secret.json \
   --build-arg OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:bdaa82a5a1df84ee304cbf842c80278e2286fede509664c5f0cf9c93c0992658 \
   -t tdx-image -f tdx/Containerfile .
```

Build for snp

```sh
podman build --authfile /tmp/pull-secret.json \
   --build-arg OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:bdaa82a5a1df84ee304cbf842c80278e2286fede509664c5f0cf9c93c0992658 \
   -t snp-image -f snp/Containerfile .
```
To add the CA certs file (say ca-certs) and Registry auth file (say config.json) to the initrd,
do the following.
```sh
podman build --authfile /tmp/pull-secret.json \
   --build-arg OCP_RELEASE_IMAGE=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:bdaa82a5a1df84ee304cbf842c80278e2286fede509664c5f0cf9c93c0992658 \
   --build-arg CA_CERTS_FILE=ca-certs --build-arg REGISTRY_AUTH_FILE=config.json \ 
   -t snp-image -f snp/Containerfile .
```