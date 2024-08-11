#!/bin/bash

MIRRORING=false
ADD_IMAGE_PULL_SECRET=false
GA_RELEASE=true
TDX=false
SNP=false
TDX_RHCOS_IMAGE=${TDX_RHCOS_IMAGE:-"quay.io/openshift_sandboxed_containers/kata-ocp416:tdx"}
SNP_RHCOS_IMAGE=${SNP_RHCOS_IMAGE:-"quay.io/openshift_sandboxed_containers/kata-ocp416:snp"}

# Function to check if the jq command is available
function check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "jq command not found. Please install the jq CLI tool."
        exit 1
    fi
}

# Function to check if the oc command is available
function check_oc() {
    if ! command -v oc &>/dev/null; then
        echo "oc command not found. Please install the oc CLI tool."
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

# Function to create runtimeClasses
function create_runtimeclasses() {
    # Variable to hold generic template for runtimeclass.
    # The `name` and `handler` fields will be updated based on the runtimeclass being created
    local runtimeclass_template='{
        "apiVersion": "node.k8s.io/v1",
        "kind": "RuntimeClass",
        "metadata": {
            "name": ""
        },
        "handler": "",
        "overhead": {
            "podFixed": {
                "cpu": "250m",
                "memory": "350Mi"
            }
        },
        "scheduling": {
            "nodeSelector": {
                "node-role.kubernetes.io/kata-oc": ""
            }
        }
    }'

    # Create kata-cc-tdx runtimeclass if TDX is set
    if [ "$TDX" = true ]; then
        local tdx_runtimeclass
        tdx_runtimeclass=$(echo "$runtimeclass_template" | jq '.metadata.name = "kata-cc-tdx" | .handler = "kata-cc-tdx"')
        oc apply -f <(echo "$tdx_runtimeclass") || exit 1
    elif [ "$SNP" = true ]; then
        # Create kata-cc-snp runtimeclass if SNP is set
        local snp_runtimeclass
        snp_runtimeclass=$(echo "$runtimeclass_template" | jq '.metadata.name = "kata-cc-snp" | .handler = "kata-cc-snp"')
        oc apply -f <(echo "$snp_runtimeclass") || exit 1
    fi

}

# Function to create Layered Image Deployment ConfigMap
function create_layered_image_deployment_configmap() {
    # Variable to hold generic template for Layered Image Deployment ConfigMap
    # The `name` and `handler` fields will be updated based on the runtimeclass being created
    local layered_image_deployment_configmap_template='{
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": "layered-image-deploy-cm",
            "namespace": "openshift-sandboxed-containers-operator"
        },
        "data": {
            "osImageURL": "",
            "kernelArguments": ""
        }
    }'

    # Create Layered Image Deployment ConfigMap for TDX
    # osImageURL: $TDX_RHCOS_IMAGE or $SNP_RHCOS_IMAGE
    # kernelArguments: "kvm_intel.tdx=1"
    if [ "$TDX" = true ]; then
        local tdx_layered_image_deployment_configmap
        tdx_layered_image_deployment_configmap=$(echo "$layered_image_deployment_configmap_template" |
            jq '.data.osImageURL = "$TDX_RHCOS_IMAGE" | .data.kernelArguments = "kvm_intel.tdx=1"')
        oc apply -f <(echo "$tdx_layered_image_deployment_configmap") || exit 1
    elif [ "$SNP" = true ]; then
        # Create Layered Image Deployment ConfigMap for SNP
        #  osImageURL: "quay.io/bpradipt/coco:ocp415"
        # kernelArguments: "kvm_intel.snp=1"
        local snp_layered_image_deployment_configmap
        snp_layered_image_deployment_configmap=$(echo "$layered_image_deployment_configmap_template" |
            jq '.data.osImageURL = "$SNP_RHCOS_IMAGE" | .data.kernelArguments = ""')
        oc apply -f <(echo "$snp_layered_image_deployment_configmap") || exit 1
    fi

    echo "Layered Image Deployment ConfigMap created successfully"

}

# Function to uninstall the installed artifacts
# It won't delete the cluster
function uninstall() {

    echo "Uninstalling all the artifacts"

    # Delete kataconfig cluster-kataconfig if it exists
    oc get kataconfig cluster-kataconfig &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        oc delete kataconfig cluster-kataconfig || exit 1
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

# Function to check coco: true label on at least one worker node
function check_coco_label() {
    local worker_nodes
    worker_nodes=$(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}')
    for node in $worker_nodes; do
        local coco_label
        coco_label=$(oc get node "$node" -o jsonpath='{.metadata.labels.coco}')
        if [ "$coco_label" == "true" ]; then
            return 0
        fi
    done
    echo "No worker node with 'coco: true' label found"
    exit 1
}

function display_help() {
    echo "Usage: install.sh [-h] [-m] [-s] [-b] [-t] [-u]"
    echo "Options:"
    echo "  -h Display help"
    echo "  -m Install the image mirroring config"
    echo "  -s Set additional cluster-wide image pull secret."
    echo "     Requires the secret to be set in PULL_SECRET_JSON environment variable"
    echo "     Example PULL_SECRET_JSON='{\"my.registry.io\": {\"auth\": \"ABC\"}}'"
    echo "  -b Use non-ga operator bundles"
    echo "  -t [tdx|snp]"
    echo "  -u Uninstall the installed artifacts. Doesn't delete the cluster"
    # Add some example usage options
    echo " "
    echo "Example usage:"
    echo "# Install the GA operator and setup TDX"
    echo " ./install.sh -t tdx"
    echo " "
    echo "# Install the GA operator with image mirroring and SNP"
    echo " ./install.sh -m -t snp"
    echo " "
    echo "# Install the GA operator with additional cluster-wide image pull secret"
    echo " export PULL_SECRET_JSON='{"brew.registry.redhat.io": {"auth": "abcd1234"}, "registry.redhat.io": {"auth": "abcd1234"}}'"
    echo " ./install.sh -s -t tdx"
    echo " "
    echo "# Deploy the pre-GA OSC operator with image mirroring and additional cluster-wide image pull secret"
    echo " export PULL_SECRET_JSON='{"brew.registry.redhat.io": {"auth": "abcd1234"}, "registry.redhat.io": {"auth": "abcd1234"}}'"
    echo " ./install.sh -m -s -b -t tdx"
    echo " "
}

while getopts "hmsbt:u" opt; do
    case $opt in
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
    u)
        echo "Uninstalling"
        uninstall
        exit 0
        ;;
    t)
        # Check if tdx or snp is passed as argument to -t
        if [ "$OPTARG" == "tdx" ]; then
            echo "Setting TDX"
            TDX=true
        elif [ "$OPTARG" == "snp" ]; then
            echo "Setting SNP"
            SNP=true
        else
            echo "Invalid argument passed to -t"
            display_help
            exit 1
        fi
        ;;

    \?)
        echo "Invalid option: -$OPTARG" >&2
        display_help
        exit 1
        ;;
    esac
done

# Check if oc command is available
check_oc

# Check if coco: true label is set on at least one worker node
check_coco_label

# Exit if neither TDX nor SNP is set
# Error out if both are set or unset
if [ "$TDX" = true ] && [ "$SNP" = true ]; then
    echo "Both TDX and SNP cannot be set at the same time"
    exit 1
elif [ "$TDX" = false ] && [ "$SNP" = false ]; then
    echo "Either TDX or SNP must be set"
    exit 1
fi

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

# Create the feature gate configmap
oc apply -f osc-fg-cm.yaml || exit 1

# Create layered image deployment configmap
create_layered_image_deployment_configmap

# Wait for the service endpoints IP to be available
wait_for_service_ep_ip webhook-service openshift-sandboxed-containers-operator || exit 1

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

# Create CoCo runtimeclasses
create_runtimeclasses

echo "Sandboxed containers operator with CoCo support is installed successfully"
