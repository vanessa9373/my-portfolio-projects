#!/bin/bash
set -e

echo "========================================="
echo "K8S-09: Deploying Advanced Scheduling Demos"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/7] Labeling nodes..."
chmod +x "${SCRIPT_DIR}/label-nodes.sh"
"${SCRIPT_DIR}/label-nodes.sh"

echo ""
echo "[2/7] Deploying node affinity demos..."
kubectl apply -f "${MANIFESTS_DIR}/node-affinity.yaml"

echo ""
echo "[3/7] Deploying pod anti-affinity demo (spread replicas)..."
kubectl apply -f "${MANIFESTS_DIR}/pod-anti-affinity.yaml"

echo ""
echo "[4/7] Deploying pod affinity demo (co-locate app + cache)..."
kubectl apply -f "${MANIFESTS_DIR}/pod-affinity.yaml"

echo ""
echo "[5/7] Deploying taints and tolerations demo..."
kubectl apply -f "${MANIFESTS_DIR}/taints-tolerations.yaml"

echo ""
echo "[6/7] Deploying topology spread constraints..."
kubectl apply -f "${MANIFESTS_DIR}/topology-spread.yaml"

echo ""
echo "[7/7] Deploying descheduler..."
kubectl apply -f "${MANIFESTS_DIR}/descheduler.yaml"

echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo ""
echo "=== Pod Placement Summary ==="
echo ""
echo "Node affinity demo pods:"
kubectl get pods -l demo -o wide 2>/dev/null || echo "  Pending (may need matching nodes)"
echo ""
echo "Anti-affinity spread:"
kubectl get pods -l app=web-spread -o wide 2>/dev/null || echo "  Pending"
echo ""
echo "Affinity co-location (app + redis):"
kubectl get pods -l 'app in (webapp,redis-cache)' -o wide 2>/dev/null || echo "  Pending"
echo ""
echo "Topology spread across zones:"
kubectl get pods -l app=zone-spread -o wide 2>/dev/null || echo "  Pending"
echo ""
echo "GPU workload:"
kubectl get pods -l workload-type=gpu -o wide 2>/dev/null || echo "  Pending (needs GPU node)"
