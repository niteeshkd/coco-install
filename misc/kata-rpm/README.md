## Create kata-containers rpm from a given srpm image

### Build the image containing the rpm
```sh
podman build --build-arg SRPM_IMAGE=<image.srpm> -t <image_with_rpm> -v $PWD:/host -f Containerfile .
```
