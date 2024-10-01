# Deploy the operator in OpenShift

Note: For vanilla Kubernetes cluster, you'll need to make
the following changes

- Install [Operator Lifecycle Manager](https://operatorhub.io/how-to-install-an-operator)
- Change the `oc` command to `kubectl` or create a temporary alias

You can run `install.sh` which will deploy the operator
or you can run the following commands individually

```sh
oc apply -f ns.yaml
oc apply -f og.yaml
oc apply -f subs-ga.yaml
```

Check for operator controller manager in `trustee-operator-system` namespace

```sh
oc get pods -n trustee-operator-system
```

## Add KBS configuration

### Create keys

```sh
openssl genpkey -algorithm ed25519 > kbs.key
openssl pkey -in kbs.key -pubout -out kbs.pem

oc create secret generic kbs-auth-public-key --from-file=kbs.pem -n trustee-operator-system
```

### Create secrets to be shared with KBS clients

Example create a secret kbsres1 with two entries. These resources (key1, key2) can be retrieved
by the KBS clients. Add secrets as per your requirements.

```sh
oc create secret generic kbsres1 --from-literal key1=res1val1 --from-literal key2=res1val2 -n trustee-operator-system
```

### Create KbsConfig CRD

Update kbsconfig.yaml to add the secret names that you want to share:
Example:

```sh
...

kbsSecretResources: ["kbsres1"]
```

```sh
oc apply -f kbsconfig.yaml
```

#### Enable permissive resource policy [Optional]

For testing with sample attester, you will have to do this:

Get the KBS deployment pod name

```sh
POD_NAME=$(oc get pods -l app=kbs -o jsonpath='{.items[0].metadata.name}' -n trustee-operator-system)
```

Allow all access to resources

```sh
oc exec -n trustee-operator-system -it "$POD_NAME" -c kbs  -- sed -i 's/false/true/g' /opa/confidential-containers/kbs/policy.rego
```

Likewise you can enable permissive policy for Attestation Service (AS) for testing

```sh
oc exec -n trustee-operator-system -it "$POD_NAME" -c as  -- sed -i 's/false/true/g' /opt/confidential-containers/attestation-service/opa/default.rego
```

#### Deploy sample kbs_client

Deploy the sample KBS client. This doesn't use any real TEE.

```sh
oc apply -f kbsclient-sim.yaml

```

#### Get secret resource from Trustee

Get the KBS service IP

```sh
KBS_SVC_IP=$(oc get svc -n trustee-operator-system kbs-service -o jsonpath={.spec.clusterIP})
echo ${KBS_SVC_IP}
```

Retrieve the secret resource

```sh
oc exec -it kbs-client -- kbs-client --url http://"REPLACE_WITH_THE_VALUE_OF_KBS_SVC_IP":8081 get-resource --path default/kbsres1/key1
```

You can check the KBS logs as well

```sh
oc logs -n trustee-operator-system $POD_NAME
```


## Custom configuration

### TDX configuration

Create the TDX configmap

```sh
oc apply -f tdx-config.yaml
```

Update the KbsConfig CR

```sh
apiVersion: confidentialcontainers.org/v1alpha1
kind: KbsConfig
metadata:
  labels:
    app.kubernetes.io/name: kbsconfig
    app.kubernetes.io/instance: kbsconfig
    app.kubernetes.io/part-of: trustee-operator
    app.kubernetes.io/managed-by: kustomize
    app.kubernetes.io/created-by: trustee-operator
  name: cluster-kbsconfig
  namespace: trustee-operator-system
spec:
  kbsConfigMapName: kbs-config-cm
  kbsAuthSecretName: kbs-auth-public-key
  kbsDeploymentType: AllInOneDeployment
  kbsRvpsRefValuesConfigMapName: rvps-reference-values
  kbsSecretResources: ["kbsres1"]
  kbsResourcePolicyConfigMapName: resource-policy

  # TDX specific configuration
  tdxConfigSpec:
     kbsTdxConfigMapName: tdx-config
 
  ```

### Custom attestation policy

Create the attestation policy configmap

```sh
oc apply -f attestation-policy.yaml
```

Update the CR

```sh
apiVersion: confidentialcontainers.org/v1alpha1
kind: KbsConfig
metadata:
  labels:
    app.kubernetes.io/name: kbsconfig
    app.kubernetes.io/instance: kbsconfig
    app.kubernetes.io/part-of: trustee-operator
    app.kubernetes.io/managed-by: kustomize
    app.kubernetes.io/created-by: trustee-operator
  name: cluster-kbsconfig
  namespace: trustee-operator-system
spec:
  kbsConfigMapName: kbs-config-cm
  kbsAuthSecretName: kbs-auth-public-key
  kbsDeploymentType: AllInOneDeployment
  kbsRvpsRefValuesConfigMapName: rvps-reference-values
  kbsSecretResources: ["kbsres1"]  
  kbsResourcePolicyConfigMapName: resource-policy

  # Override attestation policy (optional)
  kbsAttestationPolicyConfigMapName: attestation-policy
```
