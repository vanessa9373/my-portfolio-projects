#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

echo "=== Cleaning Up Operators & CRDs Lab ==="

# Remove sample MyDatabase resources
echo "[1/4] Removing MyDatabase custom resources..."
kubectl delete -f "${PROJECT_DIR}/config/samples/mydatabase-sample.yaml" --ignore-not-found
echo "Waiting for finalizers to complete..."
sleep 5

# Remove webhook configuration
echo "[2/4] Removing webhook configuration..."
kubectl delete -f "${PROJECT_DIR}/config/webhook/validating-webhook.yaml" --ignore-not-found

# Remove operator deployment
echo "[3/4] Removing operator namespace..."
kubectl delete namespace mydatabase-operator-system --ignore-not-found

# Remove CRD
echo "[4/4] Removing CustomResourceDefinition..."
kubectl delete -f "${PROJECT_DIR}/config/crd/mydatabase-crd.yaml" --ignore-not-found

# Verify cleanup
echo ""
echo "Verifying cleanup..."
kubectl get crd | grep mydatabase || echo "CRD removed successfully"
kubectl get mydatabases -A 2>/dev/null || echo "No MyDatabase resources found"

echo ""
echo "=== Cleanup Complete ==="
