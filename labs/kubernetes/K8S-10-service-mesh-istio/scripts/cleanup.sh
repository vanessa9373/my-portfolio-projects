#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=== Cleaning Up Service Mesh Lab ==="

# Remove Istio routing and policy resources
echo "[1/4] Removing Istio configuration..."
kubectl delete -f "${MANIFESTS_DIR}/fault-injection.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS_DIR}/destinationrule-circuit-breaker.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS_DIR}/virtualservice-canary.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS_DIR}/gateway.yaml" --ignore-not-found
kubectl delete -f "${MANIFESTS_DIR}/istio-peer-authentication.yaml" --ignore-not-found

# Remove application workloads
echo "[2/4] Removing sample application..."
kubectl delete -f "${MANIFESTS_DIR}/sample-app-deployment.yaml" --ignore-not-found

# Remove sidecar injection label
echo "[3/4] Disabling sidecar injection..."
kubectl label namespace default istio-injection- --ignore-not-found

# Optionally uninstall Istio
echo "[4/4] Istio uninstall (optional)..."
read -p "Uninstall Istio completely? (y/N): " UNINSTALL
if [[ "${UNINSTALL}" =~ ^[Yy]$ ]]; then
  istioctl uninstall --purge -y
  kubectl delete namespace istio-system --ignore-not-found
  echo "Istio uninstalled."
else
  echo "Istio left in place."
fi

echo ""
echo "=== Cleanup Complete ==="
