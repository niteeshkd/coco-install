## Create rhcos layered image with initrd containing CA certs and Registry auth file.

```sh
podman build --build-arg RHCOS_COCO_IMAGE=<rhcos-coco-image> \
             --build-arg CA_CERTS_FILE=<ca-certs-file> \
             --build-arg REGISTRY_AUTH_FILE=<registry-auth-file> \
             -t <new-rhcos-coco-image> -f Containerfile .
```
