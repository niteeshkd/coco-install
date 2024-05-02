# Deploy the operator in OpenShift

Note: For vanilla Kubernetes cluster, you'll need to make
the following changes

- Install [Operator Lifecycle Manager](https://operatorhub.io/how-to-install-an-operator)
- Change the `oc` command to `kubectl` or create a temporary alias

You can run `install.sh` which will deploy the operator
or you can run the following commands individually

```
oc apply -f kbs_catalog.yaml
oc apply -f ns.yaml
oc apply -f og.yaml
oc apply -f subs.yaml
```

Check for operator controller manager in `kbs-operator-system` namespace

```
oc get pods -n kbs-operator-system
```

# Allow anyuid in KBS pod

```
oc adm policy add-scc-to-user anyuid -z default -n kbs-operator-system
```

# Add KBS configuration

## Create keys

```
openssl genpkey -algorithm ed25519 > kbs.key
openssl pkey -in kbs.key -pubout -out kbs.pem

oc create secret generic kbs-auth-public-key --from-file=kbs.pem -n kbs-operator-system
```
## Create secrets to be shared with KBS clients

Example create a secret kbsres1 with two entries. These resources (key1, key2) can be retrieved
by the KBS clients. Add secrets as per your requirements.

```
oc create secret generic kbsres1 --from-literal key1=res1val1 --from-literal key2=res1val2 -n kbs-operator-system
```

## Create KbsConfig CRD

Update kbsconfig.yaml to add the secret names that you want to share:
Example:
```
...

kbsSecretResources: ["kbsres1"]
```

```
oc apply -f kbsconfig.yaml
```


Note: If planning to use latest upstream images, then run the following command
```
oc set image -n kbs-operator-system deployment/kbs-deployment kbs=ghcr.io/confidential-containers/staged-images/kbs-grpc-as:latest as=ghcr.io/confidential-containers/staged-images/coco-as-grpc:latest rvps=ghcr.io/confidential-containers/staged-images/rvps:latest
```

### Enable permissive resource policy [Optional]

For testing with sample attester, you will have to do this:

Get the KBS deployment pod name
```
POD_NAME=$(oc get pods -l app=kbs -o jsonpath='{.items[0].metadata.name}' -n kbs-operator-system)
```

Allow all access to resources
```
oc exec -n kbs-operator-system -it "$POD_NAME" -c kbs  -- sed -i 's/false/true/g' /opa/confidential-containers/kbs/policy.rego
```

Likewise you can enable permissive policy for Attestation Service (AS) for testing
```
oc exec -n kbs-operator-system -it "$POD_NAME" -c as  -- sed -i 's/false/true/g' /opt/confidential-containers/attestation-service/opa/default.rego
```

### Deploy sample kbs_client

Deploy the sample KBS client. This doesn't use any real TEE.

```
oc apply -f kbsclient-sim.yaml

```

### Get secret resource from trusty

Get the KBS service IP
```
KBS_SVC_IP=$(oc get svc -n kbs-operator-system kbs-service -o jsonpath={.spec.clusterIP})
echo ${KBS_SVC_IP}
```

Retrieve the secret resource
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

