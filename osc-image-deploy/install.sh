#!/bin/bash

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
    local timeout=300
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
    oc apply -f my_catalog.yaml || exit 1
    oc apply -f og.yaml || exit 1
    oc apply -f subs.yaml || exit 1
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

# Check if oc command is available
check_oc

# Apply the operator manifests
apply_operator_manifests

wait_for_deployment controller-manager openshift-sandboxed-containers-operator || exit 1

# Create the feature gate configmap
oc apply -f osc-fg-cm.yaml || exit 1

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

# Wait for runtimeclass kata-cc to be ready
wait_for_runtimeclass kata-cc || exit 1

echo "Sandboxed containers operator with CoCo support is installed successfully"
