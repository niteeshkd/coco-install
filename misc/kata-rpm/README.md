## Create kata-containers rpm from a given srpm image

#### Run the following (with given image.srpm) to create a image and extract the rpm into current directory.
```sh
podman build --build-arg SRPM_IMAGE=<image.srpm> -t <image_with_rpm> -v $PWD:/host -f Containerfile .
```
