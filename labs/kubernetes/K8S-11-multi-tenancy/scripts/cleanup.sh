#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"
POLICIES_DIR="${SCRIPT_DIR}/../policies"

echo "=== Cleaning Up Multi-Tenancy Lab ==="

# Remove Kyverno policies
echo "[1/5] Removing Kyverno policies..."
kubectl delete -f "${POLICIES_DIR}/kyverno-require-labels.yaml" --ignore-not-found
kubectl delete -f "${POLICIES_DIR}/kyverno-restrict-registries.yaml" --ignore-not-found
kubectl delete -f "${POLICIES_DIR}/kyverno-limit-resources.yaml" --ignore-not-found

# Remove ResourceQuotas and LimitRanges
echo "[2/5] Removing resource quotas..."
kubectl delete -f "${MANIFESTS_DIR}/tenant-resourcequota.yaml" --ignore-not-found

# Remove NetworkPolicies
echo "[3/5] Removing network policies..."
kubectl delete -f "${MANIFESTS_DIR}/tenant-networkpolicy.yaml" --ignore-not-found

# Remove vCluster if exists
echo "[4/5] Removing vCluster..."
if command -v vcluster &>/dev/null; then
  vcluster delete team-echo --namespace team-echo-vcluster 2>/dev/null || true
fi

# Remove tenant namespaces
echo "[5/5] Removing tenant namespaces..."
kubectl delete -f "${MANIFESTS_DIR}/tenant-namespace.yaml" --ignore-not-found

# Optionally uninstall Kyverno
read -p "Uninstall Kyverno? (y/N): " UNINSTALL_KYVERNO
if [[ "${UNINSTALL_KYVERNO}" =~ ^[Yy]$ ]]; then
  helm uninstall kyverno -n kyverno 2>/dev/null || true
  kubectl delete namespace kyverno --ignore-not-found
  echo "Kyverno uninstalled."
fi

echo ""
echo "=== Cleanup Complete ==="
