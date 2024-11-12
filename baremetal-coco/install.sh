#!/bin/bash

# Defaults
OCP_PULL_SECRET_LOCATION="${OCP_PULL_SECRET_LOCATION:-$HOME/pull-secret.json}"
MIRRORING=false
ADD_IMAGE_PULL_SECRET=false
GA_RELEASE=true
UPDATE_KATA_SHIM=false

# Function to check if the oc command is available
function check_oc() {
    if ! command -v oc &>/dev/null; then
        echo "oc command not found. Please install the oc CLI tool."
        exit 1
    fi
}

# Function to check if the jq command is available
function check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "jq command not found. Please install the jq CLI tool."
        exit 1
    fi
}

# Function to wait for the operator deployment object to be ready
function wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    local timeout=300
    local interval=5
    local elapsed=0
    local ready=0

    while [ $elapsed -lt $timeout ]; do
        ready=$(oc get deployment -n "$namespace" "$deployment" -o jsonpath='{.status.readyReplicas}')
        if [ "$ready" == "1" ]; then
            echo "Operator $deployment is ready"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo "Operator $deployment is not ready after $timeout seconds"
    return 1
}

# Function to wait for service endpoints IP to be available
# Example json for service endpoints. IP is available in the "addresses" field
#  "subsets": [
#    {
#        "addresses": [
#            {
#                "ip": "10.135.0.25",
#                "nodeName": "coco-worker-1.testocp.local",
#                "targetRef": {
#                    "kind": "Pod",
#                    "name": "controller-manager-87ffb6bfd-5zzvf",
#                    "namespace": "openshift-sandboxed-containers-operator",
#                    "uid": "00059394-29fb-44bf-8121-d1df02524ea8"
#                }
#            }
#        ],
#        "ports": [
#            {
#                "port": 443,
#                "protocol": "TCP"
#            }
#        ]
#    }
#]

function wait_for_service_ep_ip() {
    local service=$1
    local namespace=$2
    local timeout=300
    local interval=5
    local elapsed=0
    local ip=0

    while [ $elapsed -lt $timeout ]; do
        ip=$(oc get endpoints -n "$namespace" "$service" -o jsonpath='{.subsets[0].addresses[0].ip}')
        if [ -n "$ip" ]; then
            echo "Service $service IP is available"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo "Service $service IP is not available after $timeout seconds"
    return 1
}

# Function to wait for MachineConfigPool (MCP) to be ready
function wait_for_mcp() {
    local mcp=$1
    local timeout=900
    local interval=5
    local elapsed=0
    local ready=0
    while [ $elapsed -lt $timeout ]; do
        if [ "$statusUpdated" == "True" ] && [ "$statusUpdating" == "False" ] && [ "$statusDegraded" == "False" ]; then
            echo "MCP $mcp is ready"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        statusUpdated=$(oc get mcp "$mcp" -o=jsonpath='{.status.conditions[?(@.type=="Updated")].status}')
        statusUpdating=$(oc get mcp "$mcp" -o=jsonpath='{.status.conditions[?(@.type=="Updating")].status}')
        statusDegraded=$(oc get mcp "$mcp" -o=jsonpath='{.status.conditions[?(@.type=="Degraded")].status}')
    done

}

# Function to wait for runtimeclass to be ready
function wait_for_runtimeclass() {

    local runtimeclass=$1
    local timeout=900
    local interval=5
    local elapsed=0
    local ready=0

    # oc get runtimeclass "$runtimeclass" -o jsonpath={.metadata.name} should return the runtimeclass
    while [ $elapsed -lt $timeout ]; do
        ready=$(oc get runtimeclass "$runtimeclass" -o jsonpath='{.metadata.name}')
        if [ "$ready" == "$runtimeclass" ]; then
            echo "Runtimeclass $runtimeclass is ready"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo "Runtimeclass $runtimeclass is not ready after $timeout seconds"
    return 1
}

# Function to apply the operator manifests
function apply_operator_manifests() {
    # Apply the manifests, error exit if any of them fail
    oc apply -f ns.yaml || exit 1
    oc apply -f og.yaml || exit 1
    if [[ "$GA_RELEASE" == "true" ]]; then
        oc apply -f subs-ga.yaml || exit 1
    else
        oc apply -f osc_catalog.yaml || exit 1
        oc apply -f subs.yaml || exit 1
    fi

}

# Function to check if single node OpenShift
function is_single_node_ocp() {
    local node_count
    node_count=$(oc get nodes --no-headers | wc -l)
    if [ "$node_count" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

# Function to set additional cluster-wide image pull secret
# Requires PULL_SECRET_JSON environment variable to be set
# eg. PULL_SECRET_JSON='{"my.registry.io": {"auth": "ABC"}}'
function add_image_pull_secret() {
    # Check if SECRET_JSON is set
    if [ -z "$PULL_SECRET_JSON" ]; then
        echo "PULL_SECRET_JSON environment variable is not set"
        echo "example PULL_SECRET_JSON='{\"my.registry.io\": {\"auth\": \"ABC\"}}'"
        exit 1
    fi

    # Get the existing secret
    oc get -n openshift-config secret/pull-secret -ojson | jq -r '.data.".dockerconfigjson"' | base64 -d | jq '.' >cluster-pull-secret.json ||
        exit 1

    # Add the new secret to the existing secret
    jq --argjson data "$PULL_SECRET_JSON" '.auths |= ($data + .)' cluster-pull-secret.json >cluster-pull-secret-mod.json || exit 1

    # Set the image pull secret
    oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=cluster-pull-secret-mod.json || exit 1

}

# Function to deploy NodeFeatureDiscovery (NFD)
function deploy_node_feature_discovery() {
    echo "Node Feature Discovery operator | starting the deployment"

    pushd nfd
        oc apply -f ns.yaml || return 1
        oc apply -f og.yaml || return 1
        oc apply -f subs.yaml || return 1
        oc apply -f https://raw.githubusercontent.com/intel/intel-technology-enabling-for-openshift/main/nfd/node-feature-discovery-openshift.yaml || return 1 
    popd

    wait_for_deployment nfd-controller-manager openshift-nfd || return 1
    echo "Node Feature Discovery operator | deployment finished successfully"
}

# Function to create runtimeClass based on TEE type and
# SNO or regular OCP
# Generic template
#apiVersion: node.k8s.io/v1
#handler: kata-$TEE_TYPE
#kind: RuntimeClass
#metadata:
#  name: kata-$TEE_TYPE
#scheduling:
#  nodeSelector:
#    $label
function create_runtimeclasses() {
    local tee_type=${1}
    local label='node-role.kubernetes.io/kata-oc: ""'

    if is_single_node_ocp; then
        label='node-role.kubernetes.io/master: ""'
    fi

    # Use the label variable here, e.g., create RuntimeClass objects
    oc apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-$tee_type
handler: kata-$tee_type
scheduling:
  nodeSelector:
    $label
EOF
}

function display_help() {
    echo "Usage: install.sh -t <tee_type> [-h] [-m] [-s] [-b] [-k] [-u]"
    echo "Options:"
    echo "  -t <tee_type> Specify the TEE type (tdx or snp)"
    echo "  -h Display help"
    echo "  -m Install the image mirroring config"
    echo "  -s Set additional cluster-wide image pull secret."
    echo "     Requires the secret to be set in PULL_SECRET_JSON environment variable"
    echo "     Example PULL_SECRET_JSON='{\"my.registry.io\": {\"auth\": \"ABC\"}}'"
    echo "  -b Use pre-ga operator bundles"
    echo "  -k Updating Kata shim"
    echo "  -u Uninstall the installed artifacts"
    # Add some example usage options
    echo " "
    echo "Example usage:"
    echo "# Install the GA operator"
    echo " ./install.sh "
    echo " "
    echo "# Install the GA operator with image mirroring"
    echo " ./install.sh -m"
    echo " "
    echo "# Install the GA operator with additional cluster-wide image pull secret"
    echo " export PULL_SECRET_JSON='{"brew.registry.redhat.io": {"auth": "abcd1234"}, "registry.redhat.io": {"auth": "abcd1234"}}'"
    echo " ./install.sh -s"
    echo " "
    echo "# Install the pre-GA operator with image mirroring and additional cluster-wide image pull secret"
    echo " ./install.sh -m -s -b"
    echo " "
    echo "# Deploy the pre-GA OSC operator with image mirroring and additional cluster-wide image pull secret"
    echo " export PULL_SECRET_JSON='{"brew.registry.redhat.io": {"auth": "abcd1234"}, "registry.redhat.io": {"auth": "abcd1234"}}'"
    echo " ./install.sh -m -s -b"
    echo " "
}

# Function to verify all required variables are set and
# required files exist

function verify_params() {

    # Check if TEE_TYPE is provided
    if [ -z "$TEE_TYPE" ]; then
        echo "Error: TEE type (-t) is mandatory"
        display_help
        exit 1
    fi

    # Verify TEE_TYPE is valid
    if [ "$TEE_TYPE" != "tdx" ] && [ "$TEE_TYPE" != "snp" ]; then
        echo "Error: Invalid TEE type. It must be 'tdx' or 'snp'"
        display_help
        exit 1
    fi

    # Check if the required environment variables are set
    if [ -z "$OCP_PULL_SECRET_LOCATION" ]; then
        echo "One or more required environment variables are not set"
        exit 1
    fi

    # Check if the pull secret file exists
    if [ ! -f "$OCP_PULL_SECRET_LOCATION" ]; then
        echo "Pull secret file $OCP_PULL_SECRET_LOCATION doesn't exist"
        exit 1
    fi

    # If ADD_IMAGE_PULL_SECRET is true,  then check if PULL_SECRET_JSON is set
    if [ "$ADD_IMAGE_PULL_SECRET" = true ] && [ -z "$PULL_SECRET_JSON" ]; then
        echo "ADD_IMAGE_PULL_SECRET is set but required environment variable: PULL_SECRET_JSON is not set"
        exit 1
    fi

}

# Function to update Kata Shim
function update_kata_shim() {

    # Install daemonset for kata-shim
    oc apply -f kata-shim-ds.yaml || exit 1

    # Check if the daemonset is ready
    oc wait --for=jsonpath='{.status.numberReady}'=1 ds/kata-shim -n openshift-sandboxed-containers-operator --timeout=300s || exit 1

    # Apply the MachineConfig to update the associated crio config
    oc apply -f mc-60-kata-config.yaml || exit 1

    echo "Kata Shim is updated successfully"
}

function uninstall_node_feature_discovery() {
    oc get deployment nfd-controller-manager -n openshift-nfd &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        pushd nfd
            oc delete -f https://raw.githubusercontent.com/intel/intel-technology-enabling-for-openshift/main/nfd/node-feature-discovery-openshift.yaml || return 1 
            oc delete -f subs.yaml || return 1
            oc delete -f og.yaml || return 1
            oc delete -f ns.yaml || return 1
        popd
    fi
}

# Function to uninstall the installed artifacts
# It won't delete the cluster
function uninstall() {

    echo "Uninstalling all the artifacts"

    # Uninstall NFD
    uninstall_node_feature_discovery || exit 1

    # Delete the daemonset if it exists
    oc get ds kata-shim -n openshift-sandboxed-containers-operator &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete ds kata-shim -n openshift-sandboxed-containers-operator || exit 1
    fi

    # Delete kataconfig cluster-kataconfig if it exists
    oc get kataconfig cluster-kataconfig &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete kataconfig cluster-kataconfig || exit 1
    fi

    # Delete the MachineConfig 60-worker-kata-config if it exists
    oc get mc 60-worker-kata-config &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete mc 60-worker-kata-config || exit 1
    fi

    oc get cm osc-feature-gates -n openshift-sandboxed-containers-operator &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete cm osc-feature-gates -n openshift-sandboxed-containers-operator || exit 1
    fi

    # Delete osc-upstream-catalog CatalogSource if it exists
    oc get catalogsource osc-upstream-catalog -n openshift-marketplace &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete catalogsource osc-upstream-catalog -n openshift-marketplace || exit 1
    fi

    # Delete ImageTagMirrorSet osc-brew-registry-tag if it exists
    oc get imagetagmirrorset osc-brew-registry-tag &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete imagetagmirrorset osc-brew-registry-tag || exit 1
    fi

    # Delete ImageDigestMirrorSet osc-brew-registry-digest if it exists
    oc get imagedigestmirrorset osc-brew-registry-digest &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete imagedigestmirrorset osc-brew-registry-digest || exit 1
    fi

    # Delete the namespace openshift-sandboxed-containers-operator if it exists
    oc get ns openshift-sandboxed-containers-operator &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete ns openshift-sandboxed-containers-operator || exit 1
    fi

    echo "Waiting for MCP to be READY"

    # Wait for sometime before checking for MCP
    sleep 10
    wait_for_mcp master || exit 1
    wait_for_mcp worker || exit 1

    echo "Uninstall completed successfully"
}

# Function to print all the env variables
function print_env_vars() {
    echo "OCP_PULL_SECRET_LOCATION: $OCP_PULL_SECRET_LOCATION"
    echo "ADD_IMAGE_PULL_SECRET: $ADD_IMAGE_PULL_SECRET"
    echo "GA_RELEASE: $GA_RELEASE"
    echo "MIRRORING: $MIRRORING"
    echo "TEE_TYPE: $TEE_TYPE"
}

while getopts "t:hmsbku" opt; do
    case $opt in
    t)
        # Convert it to lower case
        TEE_TYPE=$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')
        echo "TEE type: $TEE_TYPE"
        ;;
    h)
        display_help
        exit 0
        ;;
    m)
        echo "Mirroring option passed"
        # Set global variable to indicate mirroring option is passed
        MIRRORING=true
        ;;
    s)
        echo "Setting additional cluster-wide image pull secret"
        # Check if jq command is available
        ADD_IMAGE_PULL_SECRET=true
        ;;
    b)
        echo "Using non-ga operator bundles"
        GA_RELEASE=false
        ;;
    k)
        echo "Updating Kata Shim"
        UPDATE_KATA_SHIM=true
        ;;
    u)
        echo "Uninstalling"
        uninstall
        exit 0
        ;;

    \?)
        echo "Invalid option: -$OPTARG" >&2
        display_help
        exit 1
        ;;
    esac
done

# Verify all required parameters are set
verify_params

# Check if oc command is available
check_oc

# Display the cluster information
oc cluster-info || exit 1

# If MIRRORING is true, then create the image mirroring config
if [ "$MIRRORING" = true ]; then
    echo "Creating image mirroring config"
    oc apply -f image_mirroring.yaml || exit 1

    # Sleep for sometime before checking MCP status
    sleep 10

    echo "Waiting for MCP to be ready"
    wait_for_mcp master || exit 1
    wait_for_mcp worker || exit 1
fi

# If ADD_IMAGE_PULL_SECRET is true, then add additional cluster-wide image pull secret
if [ "$ADD_IMAGE_PULL_SECRET" = true ]; then
    echo "Adding additional cluster-wide image pull secret"
    # Check if jq command is available
    check_jq
    add_image_pull_secret

    # Sleep for sometime before checking MCP status
    sleep 10

    echo "Waiting for MCP to be ready"
    wait_for_mcp master || exit 1
    wait_for_mcp worker || exit 1

fi

# Apply the operator manifests
apply_operator_manifests

wait_for_deployment controller-manager openshift-sandboxed-containers-operator || exit 1

# Wait for the service endpoints IP to be available
wait_for_service_ep_ip webhook-service openshift-sandboxed-containers-operator || exit 1

# Create CoCo feature gate ConfigMap
oc apply -f osc-fg-cm.yaml || exit 1

# Create Layered Image FG ConfigMap
if [ "$TEE_TYPE" = "tdx" ]; then
    oc apply -f layeredimage-cm-tdx.yaml || exit 1
elif [ "$TEE_TYPE" = "snp" ]; then
    oc apply -f layeredimage-cm-snp.yaml || exit 1
else
    echo "Unsupported TEE_TYPE. It must be tdx or snp" || exit 1
fi

# Create Kataconfig
oc apply -f kataconfig.yaml || exit 1

# Wait for sometime before checking for MCP
sleep 10

# If single node OpenShift, then wait for the master MCP to be ready
# Else wait for kata-oc MCP to be ready
if is_single_node_ocp; then
    echo "SNO"
    wait_for_mcp master || exit 1
else
    wait_for_mcp kata-oc || exit 1
fi

# Wait for runtimeclass kata to be ready
wait_for_runtimeclass kata || exit 1

deploy_node_feature_discovery || exit 1

# Create runtimeClass kata-tdx or kata-snp based on TEE_TYPE
create_runtimeclasses "$TEE_TYPE"

# If UPDATE_KATA_SHIM is true, then update Kata Shim
if [ "$UPDATE_KATA_SHIM" = true ]; then
    update_kata_shim

    # Wait for sometime before checking for MCP
    sleep 10
    # If single node OpenShift, then wait for the master MCP to be ready
    # Else wait for kata-oc MCP to be ready
    if is_single_node_ocp; then
        echo "SNO"
        wait_for_mcp master || exit 1
    else
        wait_for_mcp kata-oc || exit 1
    fi
fi

echo "Sandboxed containers operator with CoCo support is installed successfully"

# Print all the env variables values
print_env_vars
