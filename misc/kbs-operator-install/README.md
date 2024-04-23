# Deploy the operator in OpenShift

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

### Enable permissive resource policy

Get the KBS deployment pod name
```
POD_NAME=$(oc get pods -l app=kbs -o jsonpath='{.items[0].metadata.name}' -n kbs-operator-system)
```

Allow all access to resources
```
oc exec -n kbs-operator-system -it "$POD_NAME" -c kbs  -- sed -i 's/false/true/g' /opa/confidential-containers/kbs/policy.rego
```

### Deploy sample kbs_client

Deploy the sample client

```
oc apply -f kbsclient.yaml

```

Get the resource
```
oc exec -it -n kbs-operator-system kbs-client -- /kbs-client --url http://kbs-service:8080 get-resource --path default/kbsres1/key1
```



