# Setup KBS

## Create and configure the namespace for KBS deployment
```
oc new-project coco-kbs

# Allow anyuid in kbs pod
oc adm policy add-scc-to-user anyuid -z default -n coco-kbs
```

## Create the KBS configmap
```
kubectl apply -f kbs-cm.yaml
```


## Create certificate for KBS
```
openssl genpkey -algorithm ed25519 >kbs.key
openssl pkey -in kbs.key -pubout -out kbs.pem

# Create a secret object from the kbs.pem file.
kubectl create secret generic kbs-auth-public-key --from-file=kbs.pem -n coco-kbs
```

## Create secrets that will be sent to the application by the KBS
```

# Create an application secret
openssl rand 128 > key.bin

# Create a secret object from the user key file (key.bin).
kubectl create secret generic kbs-keys --from-file=key.bin
```

## Deploy KBS
```
kubectl apply -f kbs-deploy.yaml
```

## Get route

```
kubectl get routes -n coco-kbs -ojsonpath='{range .items[*]}{.spec.host}{"\n"}{end}'
```

You should an output like this
```
kbs-route-coco-kbs.apps.your_domain.com
```

## Add or update AA_KBC_PARAMS in peer-pods-cm configMap

```
AA_KBC_PARAMS: cc_kbc::http://kbs-route-coco-kbs.apps.your_domain.com
```

## Restart cloud-api-adaptor pods
```
kubectl set env ds/peerpodconfig-ctrl-caa-daemon -n openshift-sandboxed-containers-operator REBOOT="$(date)"
```

## Retrieving the keys from KBS

The confidential container can retrieve the key using the following
```
wget  http://127.0.0.1:8006/cdh/resource/mysecret/workload-keys/key.bin
```
