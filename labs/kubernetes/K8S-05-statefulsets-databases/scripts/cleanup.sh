#!/bin/bash
set -e

echo "========================================="
echo "K8S-05: Cleaning Up StatefulSets & Databases"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/5] Deleting MongoDB StatefulSet..."
kubectl delete statefulset mongo --ignore-not-found=true
kubectl delete service mongo-headless --ignore-not-found=true

echo ""
echo "[2/5] Deleting PostgreSQL StatefulSet..."
kubectl delete statefulset postgres --ignore-not-found=true
kubectl delete service postgres-headless --ignore-not-found=true
kubectl delete configmap postgres-config --ignore-not-found=true

echo ""
echo "[3/5] Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=postgres --timeout=60s 2>/dev/null || true
kubectl wait --for=delete pod -l app=mongo --timeout=60s 2>/dev/null || true

echo ""
echo "[4/5] Deleting Persistent Volume Claims..."
echo "WARNING: This will permanently delete all database data!"
kubectl delete pvc -l app=postgres --ignore-not-found=true
kubectl delete pvc -l app=mongo --ignore-not-found=true

echo ""
echo "[5/5] Verifying cleanup..."
echo "Remaining pods:"
kubectl get pods -l 'app in (postgres,mongo)' 2>/dev/null || echo "  None"
echo "Remaining PVCs:"
kubectl get pvc -l 'app in (postgres,mongo)' 2>/dev/null || echo "  None"

echo ""
echo "========================================="
echo "Cleanup complete!"
echo "========================================="
