#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-18: Performance Engineering & FinOps"
echo " Cleanup Script"
echo "============================================="

echo ""
echo "This will remove:"
echo "  - Bin-packing scheduler"
echo "  - VPA recommendation objects"
echo "  - Kubecost"
echo "  - Spot node pool configuration"
echo "  - Test workloads"
echo ""
echo "NOTE: Cilium removal requires cluster re-initialization"
echo "      and is NOT included in this cleanup."
echo ""
read -p "Proceed with cleanup? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Remove test workloads
echo ""
echo "[1/6] Removing test workloads..."
kubectl delete deployment bin-packed-app -n production --ignore-not-found=true 2>/dev/null || true
kubectl delete job kube-bench -n kube-system --ignore-not-found=true 2>/dev/null || true

# Remove spot node pool
echo ""
echo "[2/6] Removing spot node pool configuration..."
kubectl delete -f "$PROJECT_DIR/manifests/spot-nodepool.yaml" --ignore-not-found=true 2>/dev/null || true

# Remove bin-packing scheduler
echo ""
echo "[3/6] Removing bin-packing scheduler..."
kubectl delete -f "$PROJECT_DIR/manifests/bin-packing-scheduler.yaml" --ignore-not-found=true 2>/dev/null || true

# Remove VPA objects
echo ""
echo "[4/6] Removing VPA recommendation objects..."
kubectl delete -f "$PROJECT_DIR/manifests/vpa-recommendations.yaml" --ignore-not-found=true 2>/dev/null || true

# Uninstall Kubecost
echo ""
echo "[5/6] Uninstalling Kubecost..."
helm uninstall kubecost -n kubecost 2>/dev/null || true
kubectl delete namespace kubecost --ignore-not-found=true 2>/dev/null || true

# Remove cost allocation labels
echo ""
echo "[6/6] Removing cost allocation labels..."
for ns in production staging monitoring batch-jobs ci-cd; do
  kubectl label namespace "$ns" cost-center- department- 2>/dev/null || true
done

echo ""
echo "============================================="
echo " Cleanup complete!"
echo ""
echo " Note: Cilium was NOT removed. To fully"
echo " revert networking, you need to:"
echo "   1. helm uninstall cilium -n kube-system"
echo "   2. Reinstall kube-proxy"
echo "   3. Restart all pods"
echo "============================================="
