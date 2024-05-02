# Introduction

These are specific for TDX.
It's assumed you have setup the KBS operator, created the kbsconfig by following the
[README](./README.md)


## Create sgx_default_qcnl.conf

```
cat > sgx_default_qcnl.conf << EOF
{
  "collateral_service": "https://api.trustedservices.intel.com/sgx/certification/v4/",
  "pccs_url": "https://api.trustedservices.intel.com/sgx/certification/v4/"
  // "pccs_url": "https://localhost:8081/sgx/certification/v4/",

  // To accept insecure HTTPS certificate, set this option to false
  // "use_secure_cert": false

}
EOF
```

## Create configmap

```
oc create cm -n kbs-operator-system sgx-config --from-file=./sgx_default_qcnl.conf
```

## Patch the KBS deployment

```
oc patch -n kbs-operator-system deploy/kbs-deployment -p='
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [
          {
            "name": "sgx-config",
            "configMap": {
              "name": "sgx-config",
              "items": [
                {
                  "key": "sgx_default_qcnl.conf",
                  "path": "sgx_default_qcnl.conf"
                }
              ],
              "defaultMode": 420
            }
          }
        ],
        "containers": [
          {
            "name": "as",
            "volumeMounts": [
              {
                "name": "as-config",
                "mountPath": "/etc/as-config"
              },
              {
                "name": "sgx-config",
                "mountPath": "/etc/sgx_default_qcnl.conf",
                "subPath": "sgx_default_qcnl.conf"
              }
            ]
          }
        ]
      }
    }
  }
}
'
```

## Update KBS deployment images

```
oc set image -n kbs-operator-system deployment/kbs-deployment kbs=ghcr.io/confidential-containers/staged-images/kbs-grpc-as:latest as=quay.io/bpradipt/kbs-as:tdx rvps=ghcr.io/confidential-containers/staged-images/rvps:latest
```

## Verify E2E attesation

### Create KBS client

Create the pod

```
oc apply -f kbsclient-tdx.yaml
```

### Get secret resource from trusty

Get the KBS service IP
```
KBS_SVC_IP=$(oc get svc -n kbs-operator-system kbs-service -o jsonpath={.spec.clusterIP})
echo ${KBS_SVC_IP}
```

Retrieve secret
```
oc exec -it kbs-client -- kbs-client --url http://"REPLACE_WITH_THE_VALUE_OF_KBS_SVC_IP":8081 get-resource --path default/kbsres1/key1
```

You can check the KBS and AS logs as well

```
# KBS logs
oc logs -n kbs-operator-system deploy/kbs-deployment -c kbs

# AS logs
oc logs -n kbs-operator-system deploy/kbs-deployment -c as
```





