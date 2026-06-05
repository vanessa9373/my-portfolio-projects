#!/bin/bash
set -e

COSIGN_KEY="${COSIGN_KEY:-cosign.pub}"
NAMESPACE="${1:-production}"

echo "============================================="
echo " Image Signature Verification Report"
echo " Namespace: ${NAMESPACE}"
echo " Public Key: ${COSIGN_KEY}"
echo "============================================="

# Check cosign is available
if ! command -v cosign &>/dev/null; then
  echo "ERROR: cosign is not installed."
  echo "Install: curl -fsSL https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign"
  exit 1
fi

# Check public key exists
if [[ ! -f "${COSIGN_KEY}" ]]; then
  echo "WARNING: Public key not found at '${COSIGN_KEY}'"
  echo "Set COSIGN_KEY environment variable or provide the key file."
  echo "Proceeding with signature existence check only..."
  KEY_AVAILABLE=false
else
  KEY_AVAILABLE=true
fi

# Get all unique images in the namespace
echo ""
echo "Scanning images in namespace '${NAMESPACE}'..."
IMAGES=$(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | \
  sort -u)

if [[ -z "${IMAGES}" ]]; then
  echo "  No pods found in namespace '${NAMESPACE}'"
  exit 0
fi

TOTAL=0
SIGNED=0
UNSIGNED=0
ERRORS=0

echo ""
printf "%-60s %-12s\n" "IMAGE" "STATUS"
printf "%-60s %-12s\n" "-----" "------"

while IFS= read -r image; do
  [[ -z "${image}" ]] && continue
  TOTAL=$((TOTAL + 1))

  # Truncate long image names for display
  DISPLAY_IMAGE="${image}"
  if [[ ${#image} -gt 58 ]]; then
    DISPLAY_IMAGE="${image:0:55}..."
  fi

  if [[ "${KEY_AVAILABLE}" == "true" ]]; then
    if cosign verify --key "${COSIGN_KEY}" "${image}" &>/dev/null; then
      printf "%-60s %-12s\n" "${DISPLAY_IMAGE}" "SIGNED"
      SIGNED=$((SIGNED + 1))
    else
      printf "%-60s %-12s\n" "${DISPLAY_IMAGE}" "UNSIGNED"
      UNSIGNED=$((UNSIGNED + 1))
    fi
  else
    # Check if image has any signature (without key verification)
    if cosign tree "${image}" &>/dev/null; then
      printf "%-60s %-12s\n" "${DISPLAY_IMAGE}" "HAS_SIG"
      SIGNED=$((SIGNED + 1))
    else
      printf "%-60s %-12s\n" "${DISPLAY_IMAGE}" "NO_SIG"
      UNSIGNED=$((UNSIGNED + 1))
    fi
  fi
done <<< "${IMAGES}"

# Summary
echo ""
echo "============================================="
echo " Verification Summary"
echo "============================================="
echo "  Total images:    ${TOTAL}"
echo "  Signed:          ${SIGNED}"
echo "  Unsigned:        ${UNSIGNED}"
echo "  Errors:          ${ERRORS}"
echo ""

if [[ ${UNSIGNED} -gt 0 ]]; then
  echo "  STATUS: NON-COMPLIANT"
  echo "  ${UNSIGNED} unsigned image(s) detected."
  echo ""
  echo "  To sign an image:"
  echo "    cosign sign --key cosign.key <image>"
  exit 1
else
  echo "  STATUS: COMPLIANT"
  echo "  All images are signed."
fi

echo "============================================="
