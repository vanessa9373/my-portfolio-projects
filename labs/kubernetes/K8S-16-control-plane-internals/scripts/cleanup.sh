#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-16: Control Plane Internals Cleanup"
echo "============================================="

echo ""
read -p "This will revert control plane configurations. Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Remove etcd backup CronJob
echo ""
echo "[1/4] Removing etcd backup CronJob..."
kubectl delete -f "$PROJECT_DIR/manifests/etcd-backup-cronjob.yaml" --ignore-not-found=true 2>/dev/null || true

# Remove API Priority and Fairness custom configurations
echo ""
echo "[2/4] Removing custom API Priority and Fairness rules..."
kubectl delete -f "$PROJECT_DIR/manifests/api-priority-fairness.yaml" --ignore-not-found=true 2>/dev/null || true

# Remind about manual cleanup
echo ""
echo "[3/4] Manual cleanup required on control plane node:"
echo "  1. Remove audit policy:"
echo "     sudo rm /etc/kubernetes/audit-policy.yaml"
echo "  2. Remove audit flags from kube-apiserver manifest"
echo "  3. Remove scheduler config:"
echo "     sudo rm /etc/kubernetes/scheduler-config.yaml"
echo "  4. Remove custom scheduler flag from kube-scheduler manifest"
echo "  5. Restore backup manifests if available:"
echo "     ls /tmp/k8s-manifests-backup/"

# Clean up test resources
echo ""
echo "[4/4] Removing test resources..."
kubectl delete pod high-priority-pod --ignore-not-found=true 2>/dev/null || true
kubectl delete pod test-always-pull --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace audit-test --ignore-not-found=true 2>/dev/null || true

echo ""
echo "============================================="
echo " Cleanup complete!"
echo " Note: Some changes require manual revert on"
echo " control plane node (see instructions above)."
echo "============================================="
