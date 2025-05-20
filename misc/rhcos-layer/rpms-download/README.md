# Introduction

You can use the script to download the required rpms and copy it under {tdx,snp}/rpms folder

The current set of rpms used is available under `quay.io/bpradipt/rhcos-layer/rpms:0.2.0`
This image is created by following these steps

- Download the rpms and create a tar

Download the centos rpms used for TDX

```sh
./download-rpms.sh centos-rpms.yaml
tar czvf tdx-rpms-0.2.0.tar.gz *.rpm
```

Download the rhel rpms used for SNP

```sh
./download-rpms.sh rhel-rpms.yaml
tar czvf snp-rpms-0.2.0.tar.gz *.rpm

- Add it to a container image

Following is the Containerfile:

```sh
FROM registry.access.redhat.com/ubi9/ubi:latest

COPY tdx-rpms-0.2.0.tar.gz /tdx-rpms-0.2.0.tar.gz
COPY snp-rpms-0.2.0.tar.gz /snp-rpms-0.2.0.tar.gz
```

```sh
podman build -t quay.io/bpradipt/rhcos-layer/rpms:0.2.0 -f Containerfile .
```
