#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-17: Production Hardening & DR Cleanup"
echo "============================================="

echo ""
echo "WARNING: This will remove production hardening configurations."
echo "  - Pod Security Admission labels"
echo "  - Velero backup schedules"
echo "  - Cosign verification policies"
echo ""
read -p "Are you sure? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Remove cosign policy
echo ""
echo "[1/5] Removing image signing policy..."
kubectl delete -f "$PROJECT_DIR/manifests/cosign-policy.yaml" --ignore-not-found=true 2>/dev/null || true

# Remove Velero schedules
echo ""
echo "[2/5] Removing Velero backup schedules..."
kubectl delete -f "$PROJECT_DIR/manifests/velero-schedule.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$PROJECT_DIR/manifests/velero-backup.yaml" --ignore-not-found=true 2>/dev/null || true

# Remove PSA labels from namespaces
echo ""
echo "[3/5] Removing Pod Security Admission labels..."
for ns in production staging development; do
  kubectl label namespace "$ns" \
    pod-security.kubernetes.io/enforce- \
    pod-security.kubernetes.io/enforce-version- \
    pod-security.kubernetes.io/audit- \
    pod-security.kubernetes.io/audit-version- \
    pod-security.kubernetes.io/warn- \
    pod-security.kubernetes.io/warn-version- \
    2>/dev/null || true
done

# Remove test resources
echo ""
echo "[4/5] Removing test resources..."
kubectl delete namespace dr-test --ignore-not-found=true 2>/dev/null || true
kubectl delete secret encryption-test --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$PROJECT_DIR/manifests/pod-security-admission.yaml" --ignore-not-found=true 2>/dev/null || true

# etcd encryption cleanup notes
echo ""
echo "[5/5] Manual cleanup required:"
echo "  1. Remove etcd encryption config:"
echo "     sudo rm /etc/kubernetes/encryption-config.yaml"
echo "  2. Remove --encryption-provider-config flag from kube-apiserver"
echo "  3. To decrypt all secrets (revert to plaintext):"
echo "     - Remove aescbc provider, keep only identity provider"
echo "     - Restart API server"
echo "     - kubectl get secrets -A -o json | kubectl replace -f -"
echo ""
echo "  NOTE: Uninstalling Velero separately:"
echo "    velero uninstall"

echo ""
echo "============================================="
echo " Cleanup complete!"
echo "============================================="
