#!/bin/bash
set -e

echo "============================================"
echo "  K8S-02: Persistent Storage — Deploy All"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/7] Creating namespace and static PV..."
kubectl apply -f "${MANIFESTS_DIR}/pvc-static.yaml"   # Contains namespace + PVC
kubectl apply -f "${MANIFESTS_DIR}/pv-static.yaml"

echo ""
echo "[2/7] Waiting for static PVC to bind..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/static-pvc -n k8s-storage --timeout=30s || echo "PVC may still be pending (expected if PV was just created)"

echo ""
echo "[3/7] Deploying pod with static PVC..."
kubectl apply -f "${MANIFESTS_DIR}/pod-with-pv.yaml"

echo ""
echo "[4/7] Creating StorageClasses..."
kubectl apply -f "${MANIFESTS_DIR}/storageclass.yaml"

echo ""
echo "[5/7] Creating dynamic PVC..."
kubectl apply -f "${MANIFESTS_DIR}/pvc-dynamic.yaml"

echo ""
echo "[6/7] Deploying application with dynamic PVC..."
kubectl apply -f "${MANIFESTS_DIR}/deployment-persistent.yaml"

echo ""
echo "[7/7] Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=storage-demo -n k8s-storage --timeout=120s || true
kubectl wait --for=condition=Ready pod -l app=persistent-app -n k8s-storage --timeout=120s || true

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "--- PersistentVolumes ---"
kubectl get pv
echo ""
echo "--- PersistentVolumeClaims ---"
kubectl get pvc -n k8s-storage
echo ""
echo "--- StorageClasses ---"
kubectl get storageclass
echo ""
echo "--- Pods ---"
kubectl get pods -n k8s-storage
echo ""
echo "Next: Run ./test-persistence.sh to verify data survives pod deletion"
echo ""
