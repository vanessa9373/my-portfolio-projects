#!/bin/bash
set -e

echo "========================================="
echo "K8S-05: Deploying StatefulSets & Databases"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/6] Creating PostgreSQL headless service..."
kubectl apply -f "${MANIFESTS_DIR}/headless-service.yaml"

echo ""
echo "[2/6] Creating PostgreSQL ConfigMap..."
kubectl apply -f "${MANIFESTS_DIR}/postgres-configmap.yaml"

echo ""
echo "[3/6] Deploying PostgreSQL StatefulSet (3 replicas)..."
kubectl apply -f "${MANIFESTS_DIR}/postgres-statefulset.yaml"

echo ""
echo "[4/6] Waiting for PostgreSQL pods to be ready..."
kubectl rollout status statefulset/postgres --timeout=180s

echo ""
echo "[5/6] Creating MongoDB headless service and StatefulSet..."
kubectl apply -f "${MANIFESTS_DIR}/mongo-headless-service.yaml"
kubectl apply -f "${MANIFESTS_DIR}/mongo-statefulset.yaml"

echo ""
echo "[6/6] Waiting for MongoDB pods to be ready..."
kubectl rollout status statefulset/mongo --timeout=180s

echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo ""
echo "PostgreSQL pods:"
kubectl get pods -l app=postgres -o wide
echo ""
echo "MongoDB pods:"
kubectl get pods -l app=mongo -o wide
echo ""
echo "Persistent Volume Claims:"
kubectl get pvc -l 'app in (postgres,mongo)'
echo ""
echo "Next steps:"
echo "  1. Initialize MongoDB ReplicaSet: kubectl exec mongo-0 -- mongosh --eval 'rs.initiate(...)'"
echo "  2. Run failover tests: ./scripts/test-failover.sh"
