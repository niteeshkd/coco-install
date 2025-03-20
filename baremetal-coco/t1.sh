#!/bin/bash
SIGNATURE_VERIFICATION="${SIGNATURE_VERIFICATION:-false}"
trustee_url="${TRUSTEE_URL:-"http://kbs-service:8080"}"

if [ "$SIGNATURE_VERIFICATION" = true ]; then
    kata_override="[hypervisor.qemu]
kernel_params= \"agent.aa_kbc_params=cc_kbc::$trustee_url agent.enable_signature_verification=true\""
else
    kata_override="[hypervisor.qemu]
kernel_params= \"agent.aa_kbc_params=cc_kbc::$trustee_url\""
fi
echo $kata_override
