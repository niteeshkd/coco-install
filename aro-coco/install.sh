#!/bin/bash

# Defaults
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-aro-rg-$(shuf -i 1000-9999 -n 1)}"
AZURE_REGION="${AZURE_REGION:-eastus}"
ARO_VNET="${ARO_VNET:-aro-vnet}"
ARO_VNET_CIDR="${ARO_VNET_CIDR:-10.0.0.0/22}"
ARO_MASTER_SUBNET="${ARO_MASTER_SUBNET:-master-subnet}"
ARO_MASTER_SUBNET_CIDR="${ARO_MASTER_SUBNET_CIDR:-10.0.0.0/23}"
ARO_WORKER_SUBNET="${ARO_WORKER_SUBNET:-worker-subnet}"
ARO_WORKER_SUBNET_CIDR="${ARO_WORKER_SUBNET_CIDR:-10.0.2.0/23}"
ARO_CLUSTER_NAME="${ARO_CLUSTER_NAME:-aro-cluster}"
ARO_VERSION="${ARO_VERSION:-4.14.16}"
OCP_PULL_SECRET_LOCATION="${OCP_PULL_SECRET_LOCATION:-$HOME/pull-secret.json}"
MIRRORING=false
ADD_IMAGE_PULL_SECRET=false
GA_RELEASE=true

# Function to check if the oc command is available
function check_oc() {
    if ! command -v oc &>/dev/null; then
        echo "oc command not found. Please install the oc CLI tool."
        exit 1
    fi
}

# Function to check if the az command is available
function check_az() {
    if ! command -v az &>/dev/null; then
        echo "az command not found. Please install the az CLI tool."
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
    local timeout=300
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

# ARO specific functions

# Function to register the MS providers for ARO
function register_provders() {
    az provider register -n Microsoft.RedHatOpenShift --wait || exit 1
    az provider register -n Microsoft.Compute --wait || exit 1
    az provider register -n Microsoft.Storage --wait || exit 1
    az provider register -n Microsoft.Authorization --wait || exit 1
}

# Function to create resource group for ARO
function create_resource_group() {
    local resource_group=$1
    local location=$2

    # If RESOURCE_GROUP or location is empty then exit
    if [ -z "$resource_group" ] || [ -z "$location" ]; then
        echo "Resource group or location is empty"
        exit 1
    fi

    # Return if resource group already exists
    az group show --name "$resource_group"

    return_code=$?
    if [ $return_code -eq 0 ]; then
        echo "Resource group $resource_group already exists"
        return
    fi

    az group create --name "$resource_group" --location "$location" || exit 1
}

# Function to create virtual network for ARO
function create_virtual_network() {
    local resource_group=$1
    local vnet_name=$2
    local vnet_cidr=$3
    # If any of the parameters are empty then exit
    if [ -z "$resource_group" ] || [ -z "$vnet_name" ] ||
        [ -z "$vnet_cidr" ]; then
        echo "Resource group, vnet name, vnet cidr, subnet name or subnet cidr is empty"
        exit 1
    fi
    az network vnet create --resource-group "$resource_group" \
        --name "$vnet_name" \
        --address-prefixes "$vnet_cidr" || exit 1
}

# Function to create empty subnet
function create_empty_subnet() {
    local resource_group=$1
    local vnet_name=$2
    local subnet_name=$3
    local subnet_cidr=$4
    # If any of the parameters are empty then exit
    if [ -z "$resource_group" ] || [ -z "$vnet_name" ] ||
        [ -z "$subnet_name" ] || [ -z "$subnet_cidr" ]; then
        echo "Resource group, vnet name, subnet name or subnet cidr is empty"
        exit 1
    fi
    az network vnet subnet create --resource-group "$resource_group" \
        --vnet-name "$vnet_name" \
        --name "$subnet_name" \
        --address-prefixes "$subnet_cidr" || exit 1
}

# Function to check if ARO cluster with the name exists in the resource group and region
function check_aro_cluster_exists() {
    local resource_group=$1
    local cluster_name=$2
    # If any of the parameters are empty then exit
    if [ -z "$resource_group" ] || [ -z "$cluster_name" ]; then
        echo "Resource group or cluster name is empty"
        exit 1
    fi

    # Print cluster name if it exists
    az aro show --resource-group "$resource_group" --name "$cluster_name" &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        echo "Cluster ($cluster_name) exists in resource group $resource_group"
        return 0
    fi
    echo "Cluster ($cluster_name) doesn't exist in resource group $resource_group"
    return 1
}

# Function to create ARO cluster
function create_aro_cluster() {
    local resource_group=$1
    local cluster_name=$2
    local vnet_name=$3
    local master_subnet=$4
    local worker_subnet=$5
    local pull_secret=$6
    local aro_version=$7
    # If any of the parameters are empty then exit
    if [ -z "$resource_group" ] || [ -z "$cluster_name" ] ||
        [ -z "$vnet_name" ] || [ -z "$master_subnet" ] || [ -z "$worker_subnet" ] ||
        [ -z "$pull_secret" ] || [ -z "$aro_version" ]; then
        echo "Resource group, cluster name, vnet name, master subnet, worker subnet, pull secret or version is empty"
        exit 1
    fi

    az aro create --resource-group "$resource_group" \
        --name "$cluster_name" \
        --vnet "$vnet_name" \
        --master-subnet "$master_subnet" \
        --worker-subnet "$worker_subnet" \
        --pull-secret "$pull_secret" \
        --version "$aro_version" || exit 1
}

# Function to download kubeconfig for ARO cluster
function download_kubeconfig() {
    local resource_group=$1
    local cluster_name=$2
    local kubeconfig_file=$3

    echo "Downloading kubeconfig for ARO cluster $cluster_name in resource group $resource_group"
    # If any of the parameters are empty then exit
    if [ -z "$resource_group" ] || [ -z "$cluster_name" ] || [ -z "$kubeconfig_file" ]; then
        echo "Resource group, cluster name or kubeconfig file is empty"
        exit 1
    fi

    # If the kubeconfig file already exists then display a message and return
    if [ -f "$kubeconfig_file" ]; then
        echo "Kubeconfig file $kubeconfig_file already exists. Not downloading again"
        return
    fi

    az aro get-admin-kubeconfig --resource-group "$resource_group" \
        -n "$cluster_name" -f "$kubeconfig_file" || exit 1
}

# Function to build the peer-pods-secret Secret
function build_peer_pods_secret() {
    AZURE_CLIENT_ID=$(oc get secret -n kube-system azure-credentials -o jsonpath="{.data.azure_client_id}" | base64 -d)
    AZURE_CLIENT_SECRET=$(oc get secret -n kube-system azure-credentials -o jsonpath="{.data.azure_client_secret}" | base64 -d)
    AZURE_TENANT_ID=$(oc get secret -n kube-system azure-credentials -o jsonpath="{.data.azure_tenant_id}" | base64 -d)
    AZURE_SUBSCRIPTION_ID=$(oc get secret -n kube-system azure-credentials -o jsonpath="{.data.azure_subscription_id}" | base64 -d)

    echo "AZURE_CLIENT_ID: \"$AZURE_CLIENT_ID\""
    echo "AZURE_CLIENT_SECRET: \"$AZURE_CLIENT_SECRET\""
    echo "AZURE_TENANT_ID: \"$AZURE_TENANT_ID\""
    echo "AZURE_SUBSCRIPTION_ID: \"$AZURE_SUBSCRIPTION_ID\""

    # Verify if the values are not empty
    if [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || [ -z "$AZURE_TENANT_ID" ] || [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
        echo "peer-pods-secret required inputs are empty"
        exit 1
    fi

    # Check if the secret already exists
    oc get secret peer-pods-secret -n openshift-sandboxed-containers-operator &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        echo "peer-pods-secret Secret already exists"
        return
    fi

    # Use the above values to create peer-pods-secret Secret in the openshift-sandboxed-containers-operator namespace
    oc create secret generic peer-pods-secret -n openshift-sandboxed-containers-operator \
        --from-literal=AZURE_CLIENT_ID="$AZURE_CLIENT_ID" \
        --from-literal=AZURE_CLIENT_SECRET="$AZURE_CLIENT_SECRET" \
        --from-literal=AZURE_TENANT_ID="$AZURE_TENANT_ID" \
        --from-literal=AZURE_SUBSCRIPTION_ID="$AZURE_SUBSCRIPTION_ID" || exit 1

    echo "peer-pods-secret Secret created successfully"

    echo "Note: When ARO cluster is deleted, the secret object gets deleted as well. \
    Ensure you safely store the above values so that these are available for any CoCo related resource cleanups."

}

# Function to build the peer-pods-cm ConfigMap
function build_peer_pods_cm {

    # Get the ARO created RG
    ARO_RESOURCE_GROUP=$(oc get infrastructure/cluster -o jsonpath='{.status.platformStatus.azure.resourceGroupName}')

    # Get VNET name used by ARO. This exists in the admin created RG
    ARO_VNET_NAME=$(az network vnet list --resource-group "$AZURE_RESOURCE_GROUP" --query "[].{Name:name}" --output tsv)

    # Get the OpenShift worker subnet ip address cidr. This exists in the admin created RG
    ARO_WORKER_SUBNET_ID=$(az network vnet subnet list --resource-group "$AZURE_RESOURCE_GROUP" \
        --vnet-name "$ARO_VNET_NAME" --query "[].{Id:id} | [? contains(Id, 'worker')]" --output tsv)

    ARO_NSG_ID=$(az network nsg list --resource-group "$ARO_RESOURCE_GROUP" --query "[].{Id:id}" --output tsv)

    echo "AZURE_REGION: \"$AZURE_REGION\""
    echo "AZURE_RESOURCE_GROUP: \"$ARO_RESOURCE_GROUP\""
    echo "AZURE_SUBNET_ID: \"$ARO_WORKER_SUBNET_ID\""
    echo "AZURE_NSG_ID: \"$ARO_NSG_ID\""

    # Verify if the values are not empty
    if [ -z "$AZURE_REGION" ] || [ -z "$ARO_RESOURCE_GROUP" ] || [ -z "$ARO_WORKER_SUBNET_ID" ] || [ -z "$ARO_NSG_ID" ]; then
        echo "peer-pods-cm required inputs are empty"
        exit 1
    fi

    # The peer-pods-cm consists of the following
    # CLOUD_PROVIDER: "azure"
    # VXLAN_PORT: "9000"
    # AZURE_INSTANCE_SIZE: "Standard_DC2as_v5"
    # AZURE_RESOURCE_GROUP: "${ARO_RESOURCE_GROUP}"
    # AZURE_REGION: "${AZURE_REGION}"
    # AZURE_SUBNET_ID: "${ARO_WORKER_SUBNET_ID}"
    # AZURE_NSG_ID: "${ARO_NSG_ID}"
    # DISABLECVM: "false"
    # AZURE_IMAGE_ID: ""
    # PROXY_TIMEOUT: "5m"

    # Check if the ConfigMap already exists
    oc get configmap peer-pods-cm -n openshift-sandboxed-containers-operator &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        echo "peer-pods-cm ConfigMap already exists"
        return
    fi

    # Use the above values to create peer-pods-cm ConfigMap in the openshift-sandboxed-containers-operator namespace
    oc create configmap peer-pods-cm -n openshift-sandboxed-containers-operator \
        --from-literal=CLOUD_PROVIDER="azure" \
        --from-literal=VXLAN_PORT="9000" \
        --from-literal=AZURE_INSTANCE_SIZE="Standard_DC2as_v5" \
        --from-literal=AZURE_RESOURCE_GROUP="${ARO_RESOURCE_GROUP}" \
        --from-literal=AZURE_REGION="${AZURE_REGION}" \
        --from-literal=AZURE_SUBNET_ID="${ARO_WORKER_SUBNET_ID}" \
        --from-literal=AZURE_NSG_ID="${ARO_NSG_ID}" \
        --from-literal=DISABLECVM="false" \
        --from-literal=AZURE_IMAGE_ID="" \
        --from-literal=PROXY_TIMEOUT="5m" || exit 1

    echo "peer-pods-cm ConfigMap created successfully"
}

# Function to create ssh key secret
function create_ssh_key_secret() {

    # Check if the ssh-key-secret already exists

    oc get secret ssh-key-secret -n openshift-sandboxed-containers-operator &>/dev/null
    return_code=$?
    if [ $return_code -eq 0 ]; then
        echo "ssh-key-secret Secret already exists"
        return
    fi

    # Use ssh-keygen to generate the ssh key pair in the current directory
    # Both the private and public keys should be stored in the current directory from where
    # this script is run

    # Generate the ssh key pair
    ssh-keygen -t rsa -b 4096 -f id_rsa -N ""

    # Create the secret
    oc create secret generic ssh-key-secret -n openshift-sandboxed-containers-operator \
        --from-file=id_rsa=id_rsa \
        --from-file=id_rsa.pub=id_rsa.pub || exit 1

    echo "Both the SSH public key and private key are part of the ssh-key-secret"
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

function display_help() {
    echo "Usage: install.sh [-h] [-m] [-s]"
    echo "Options:"
    echo "  -h Display help"
    echo "  -m Install the image mirroring config"
    echo "  -s Set additional cluster-wide image pull secret."
    echo "     Requires the secret to be set in PULL_SECRET_JSON environment variable"
    echo "     Example PULL_SECRET_JSON='{\"my.registry.io\": {\"auth\": \"ABC\"}}'"
    echo "  -b Use non-ga operator bundles"
    echo "  -d Delete ARO cluster"
}

# Function to verify all required variables are set and
# required files exist

function verify_params() {

    # Check if the required environment variables are set
    if [ -z "$AZURE_RESOURCE_GROUP" ] ||
        [ -z "$AZURE_REGION" ] ||
        [ -z "$ARO_VNET" ] ||
        [ -z "$ARO_VNET_CIDR" ] ||
        [ -z "$ARO_MASTER_SUBNET" ] ||
        [ -z "$ARO_MASTER_SUBNET_CIDR" ] ||
        [ -z "$ARO_WORKER_SUBNET" ] ||
        [ -z "$ARO_WORKER_SUBNET_CIDR" ] ||
        [ -z "$ARO_CLUSTER_NAME" ] ||
        [ -z "$ARO_VERSION" ] ||
        [ -z "$OCP_PULL_SECRET_LOCATION" ]; then
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

# Function to delete ARO cluster
function delete_aro_cluster() {
    local resource_group=$1
    local cluster_name=$2

    # If any of the parameters are empty then exit
    if [ -z "$resource_group" ] || [ -z "$cluster_name" ]; then
        echo "Resource group or cluster name is empty"
        exit 1
    fi

    az aro delete --resource-group "$resource_group" --name "$cluster_name" --yes || exit 1
}

while getopts "hmsbd" opt; do
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
    d)
        echo "Deleting ARO cluster"
        delete_aro_cluster "$AZURE_RESOURCE_GROUP" "$ARO_CLUSTER_NAME"
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

# Check if az command is available
check_az

# Register the MS providers for ARO
register_provders

# Create resource group for ARO
create_resource_group "$AZURE_RESOURCE_GROUP" "$AZURE_REGION"

if ! check_aro_cluster_exists "$AZURE_RESOURCE_GROUP" "$ARO_CLUSTER_NAME"; then

    echo "Creating ARO cluster $ARO_CLUSTER_NAME in resource group $AZURE_RESOURCE_GROUP"
    # Create virtual network for ARO
    create_virtual_network "$AZURE_RESOURCE_GROUP" "$ARO_VNET" "$ARO_VNET_CIDR"

    # Create master subnet for ARO
    create_empty_subnet "$AZURE_RESOURCE_GROUP" "$ARO_VNET" "$ARO_MASTER_SUBNET" "$ARO_MASTER_SUBNET_CIDR"

    # Create worker subnet for ARO
    create_empty_subnet "$AZURE_RESOURCE_GROUP" "$ARO_VNET" "$ARO_WORKER_SUBNET" "$ARO_WORKER_SUBNET_CIDR"

    # Create ARO cluster
    create_aro_cluster "$AZURE_RESOURCE_GROUP" "$ARO_CLUSTER_NAME" \
        "$ARO_VNET" "$ARO_MASTER_SUBNET" "$ARO_WORKER_SUBNET" "$OCP_PULL_SECRET_LOCATION" "$ARO_VERSION"
else
    echo "ARO cluster $ARO_CLUSTER_NAME already exists in resource group $AZURE_RESOURCE_GROUP"
fi

# The above command is synchronous and will wait till ARO cluster is ready

# Download the kubeconfig for the ARO cluster
KUBECONFIG_FILE=${ARO_CLUSTER_NAME}-kubeconfig
download_kubeconfig "$AZURE_RESOURCE_GROUP" "$ARO_CLUSTER_NAME" "$KUBECONFIG_FILE"

# Set the KUBECONFIG environment variable
export KUBECONFIG=$KUBECONFIG_FILE

# Display the cluster information
oc cluster-info

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

# Build peer-pods-secret Secret
build_peer_pods_secret

# Build peer-pods-cm ConfigMap
build_peer_pods_cm

# Create ssh key secret
create_ssh_key_secret

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

# Wait for runtimeclass kata-remote to be ready
wait_for_runtimeclass kata-remote || exit 1

echo "Sandboxed containers operator with CoCo support is installed successfully"
