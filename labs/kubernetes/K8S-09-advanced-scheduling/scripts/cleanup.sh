#!/bin/bash
set -e

echo "========================================="
echo "K8S-09: Cleaning Up Advanced Scheduling Resources"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/7] Deleting descheduler..."
kubectl delete -f "${MANIFESTS_DIR}/descheduler.yaml" --ignore-not-found=true 2>/dev/null || true

echo ""
echo "[2/7] Deleting topology spread demo..."
kubectl delete -f "${MANIFESTS_DIR}/topology-spread.yaml" --ignore-not-found=true

echo ""
echo "[3/7] Deleting taints and tolerations demo..."
kubectl delete -f "${MANIFESTS_DIR}/taints-tolerations.yaml" --ignore-not-found=true

echo ""
echo "[4/7] Deleting pod affinity demo..."
kubectl delete -f "${MANIFESTS_DIR}/pod-affinity.yaml" --ignore-not-found=true

echo ""
echo "[5/7] Deleting pod anti-affinity demo..."
kubectl delete -f "${MANIFESTS_DIR}/pod-anti-affinity.yaml" --ignore-not-found=true

echo ""
echo "[6/7] Deleting node affinity demo..."
kubectl delete -f "${MANIFESTS_DIR}/node-affinity.yaml" --ignore-not-found=true

echo ""
echo "[7/7] Removing node taints and labels..."
NODES=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
for NODE in ${NODES}; do
  kubectl taint nodes "${NODE}" gpu=nvidia:NoSchedule- 2>/dev/null || true
  kubectl label node "${NODE}" disk- gpu- environment- --overwrite 2>/dev/null || true
  echo "  Cleaned labels/taints from ${NODE}"
done

echo ""
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=web-spread --timeout=60s 2>/dev/null || true
kubectl wait --for=delete pod -l app=zone-spread --timeout=60s 2>/dev/null || true

echo ""
echo "========================================="
echo "Cleanup complete!"
echo "========================================="
echo ""
echo "Remaining scheduling demo pods:"
kubectl get pods -l 'app in (web-spread,zone-spread,webapp,redis-cache,ml-training,scheduling-demo)' 2>/dev/null || echo "  None"
