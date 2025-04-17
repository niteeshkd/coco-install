## Create kata-containers rpm from a given srpm image

### Build the image containing the rpm
```sh
podman build --build-arg SRPM_IMAGE=<image.srpm> -t <image_with_rpm> -f Containerfile .
```

### Get the rpm built under a directory (e.g. PWD)
```sh
podman run -v $PWD:/host -it <image_with_rpm> cp -r /root/rpmbuild/RPMS /host
```
The rpm will be copied under PWD/RPMS/.