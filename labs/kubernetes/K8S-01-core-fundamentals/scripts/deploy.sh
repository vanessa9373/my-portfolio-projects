#!/bin/bash
set -e

echo "============================================"
echo "  K8S-01: Core Fundamentals — Deploy All"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/6] Creating namespace..."
kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"

echo ""
echo "[2/6] Setting context to k8s-fundamentals namespace..."
kubectl config set-context --current --namespace=k8s-fundamentals

echo ""
echo "[3/6] Creating ConfigMap..."
kubectl apply -f "${MANIFESTS_DIR}/configmap.yaml"

echo ""
echo "[4/6] Creating Secret..."
kubectl apply -f "${MANIFESTS_DIR}/secret.yaml"

echo ""
echo "[5/6] Creating Deployment (3 replicas)..."
kubectl apply -f "${MANIFESTS_DIR}/deployment.yaml"

echo ""
echo "[6/6] Creating Services (ClusterIP + NodePort)..."
kubectl apply -f "${MANIFESTS_DIR}/service-clusterip.yaml"
kubectl apply -f "${MANIFESTS_DIR}/service-nodeport.yaml"

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "Waiting for pods to be ready..."
kubectl rollout status deployment/web-app -n k8s-fundamentals --timeout=120s

echo ""
echo "--- Resources Created ---"
kubectl get all -n k8s-fundamentals
echo ""
echo "--- ConfigMaps & Secrets ---"
kubectl get configmaps,secrets -n k8s-fundamentals

echo ""
echo "Access the application:"
echo "  Internal: kubectl run test --rm -it --image=busybox --restart=Never -- wget -qO- http://web-app-internal.k8s-fundamentals"
echo "  External: curl http://<node-ip>:30080"
echo ""
