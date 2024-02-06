#!/bin/bash
#

# Function to check if peer-pods-cm configmap exists
function check_peer_pods_cm_exists() {
  if kubectl get configmap peer-pods-cm -n openshift-sandboxed-containers-operator >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Function to check if podvm-images configmap exists
function check_podvm_images_exists() {
  if kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# function to create podvm image

function create_podvm_image() {
  case "${CLOUD_PROVIDER}" in
  azure)
    echo "Creating Azure image"
    /scripts/azure-podvm-image-handler.sh -c
    if [ "${UPDATE_PEERPODS_CM}" == "yes" ]; then
      # Check if peer-pods-cm configmap exists
      if ! check_peer_pods_cm_exists; then
        echo "peer-pods-cm configmap does not exist. Skipping the update of peer-pods-cm"
        exit 0
      fi
      # Get the IMAGE_ID value from the podvm-images configmap
      # key: azure and the first value in the list
      IMAGE_ID=$(kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator -o jsonpath='{.data.azure}' | awk '{print $1}')
      # Update peer-pods-cm configmap with the IMAGE_ID value
      echo "Updating peer-pods-cm configmap with IMAGE_ID=${IMAGE_ID}"
      kubectl patch configmap peer-pods-cm -n openshift-sandboxed-containers-operator --type merge -p "{\"data\":{\"AZURE_IMAGE_ID\":\"${IMAGE_ID}\"}}"
    fi
    ;;
  aws)
    echo "Creating AWS AMI"
    /scripts/aws-podvm-image-handler.sh -c
    if [ "${UPDATE_PEERPODS_CM}" == "yes" ]; then
      # Check if peer-pods-cm configmap exists
      if ! check_peer_pods_cm_exists; then
        echo "peer-pods-cm configmap does not exist. Skipping the update of peer-pods-cm"
        exit 0
      fi
      # Get the AMI_ID value from the podvm-images configmap
      # key: aws and the first value in the list
      AMI_ID=$(kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator -o jsonpath='{.data.aws}' | awk '{print $1}')
      # Update peer-pods-cm configmap with the AMI_ID value
      echo "Updating peer-pods-cm configmap with AMI_ID=${AMI_ID}"
      kubectl patch configmap peer-pods-cm -n openshift-sandboxed-containers-operator --type merge -p "{\"data\":{\"PODVM_AMI_ID\":\"${AMI_ID}\"}}"
    fi
    ;;
  *)
    echo "CLOUD_PROVIDER is not set to azure or aws"
    exit 1
    ;;
  esac
}

# Function to delete podvm image
# IMAGE_ID or AMI_ID is the input and expected to be set
# These are checked in individual cloud provider scripts and if not set, the script will exit

function delete_podvm_image() {

  # Check for the existence of peer-pods-cm and podvm-images configmap. If not present, then exit
  if ! check_peer_pods_cm_exists; then
    echo "peer-pods-cm configmap does not exist. Skipping image deletion"
    exit 0
  fi

  if ! check_podvm_images_exists; then
    echo "podvm-images configmap does not exist. Skipping image deletion"
    exit 0
  fi

  case "${CLOUD_PROVIDER}" in
  azure)
    # check if the AZURE_IMAGE_ID value in peer-pods-cm is same as the input IMAGE_ID
    # If yes, then don't delete the image unless force option is provided
    AZURE_IMAGE_ID=$(kubectl get configmap peer-pods-cm -n openshift-sandboxed-containers-operator -o jsonpath='{.data.AZURE_IMAGE_ID}')
    if [ "${AZURE_IMAGE_ID}" == "${IMAGE_ID}" ]; then
      if [ "$1" != "-f" ]; then
        echo "AZURE_IMAGE_ID in peer-pods-cm is same as the input image to be deleted. Skipping the deletion of Azure image"
        exit 0
      fi
    fi

    echo "Deleting Azure image"
    /scripts/azure-podvm-image-handler.sh -C
    # Update the podvm-images configmap to remove the azure image id from the list
    # Get the IMAGE_ID_LIST from the podvm-images configmap
    IMAGE_ID_LIST=$(kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator -o jsonpath='{.data.azure}')

    # Remove the IMAGE_ID from the list
    IMAGE_ID_LIST="${IMAGE_ID_LIST//${IMAGE_ID}/}"

    # Update the podvm-images configmap with the new list
    kubectl patch configmap podvm-images -n openshift-sandboxed-containers-operator --type merge -p "{\"data\":{\"azure\":\"${IMAGE_ID_LIST}\"}}"

    # Update the peer-pods-cm configmap and remove the AZURE_IMAGE_ID value
    if [ "${UPDATE_PEERPODS_CM}" == "yes" ]; then
      kubectl patch configmap peer-pods-cm -n openshift-sandboxed-containers-operator --type merge -p "{\"data\":{\"AZURE_IMAGE_ID\":\"\"}}"
    fi

    ;;
  aws)
    # check if the PODVM_AMI_ID value in peer-pods-cm is same as the input AMI_ID
    # If yes, then don't delete the image unless force option is provided
    PODVM_AMI_ID=$(kubectl get configmap peer-pods-cm -n openshift-sandboxed-containers-operator -o jsonpath='{.data.PODVM_AMI_ID}')
    if [ "${PODVM_AMI_ID}" == "${AMI_ID}" ]; then
      if [ "$1" != "-f" ]; then
        echo "PODVM_AMI_ID in peer-pods-cm is same as the input image to be deleted. Skipping the deletion of AWS AMI"
        exit 0
      fi
    fi

    echo "Deleting AWS AMI"
    /scripts/aws-podvm-image-handler.sh -C
    # Update the podvm-images configmap to remove the AWS AMI id from the list
    # Get the AMI_ID_LIST from the podvm-images configmap
    AMI_ID_LIST=$(kubectl get configmap podvm-images -n openshift-sandboxed-containers-operator -o jsonpath='{.data.aws}')

    # Remove the AMI_ID from the list
    AMI_ID_LIST="${AMI_ID_LIST//${AMI_ID}/}"

    # Update the podvm-images configmap with the new list
    kubectl patch configmap podvm-images -n openshift-sandboxed-containers-operator --type merge -p "{\"data\":{\"aws\":\"${AMI_ID_LIST}\"}}"

    # Update the peer-pods-cm configmap and remove the PODVM_AMI_ID value
    if [ "${UPDATE_PEERPODS_CM}" == "yes" ]; then
      kubectl patch configmap peer-pods-cm -n openshift-sandboxed-containers-operator --type merge -p "{\"data\":{\"PODVM_AMI_ID\":\"\"}}"
    fi

    ;;
  *)
    echo "CLOUD_PROVIDER is not set to azure or aws"
    exit 1
    ;;
  esac
}

# Delete the podvm image gallery in Azure

function delete_podvm_image_gallery() {
  echo "Deleting Azure image gallery"
  # Check if CLOUD_PROVIDER is set to azure, otherwise return
  if [ "${CLOUD_PROVIDER}" != "azure" ]; then
    echo "CLOUD_PROVIDER is not Azure"
    return
  fi

  # Check if force option is passed
  if [ "$1" == "-f" ]; then
    /scripts/azure-podvm-image-handler.sh -G force
  else
    /scripts/azure-podvm-image-handler.sh -G
  fi
}

# Call the function to create or delete podvm image based on argument

case "$1" in
create)
  create_podvm_image
  ;;
delete)
  delete_podvm_image "$2"
  ;;
delete-gallery)
  delete_podvm_image_gallery "$2"
  ;;
*)
  echo "Usage: $0 {create|delete [-f]|delete-gallery [-f]}"
  exit 1
  ;;
esac
