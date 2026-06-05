#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

echo "=== Deploying Operators & CRDs Lab ==="

# Step 1: Apply the CRD
echo "[1/4] Registering CustomResourceDefinition..."
kubectl apply -f "${PROJECT_DIR}/config/crd/mydatabase-crd.yaml"
kubectl wait --for=condition=established crd/mydatabases.database.example.com --timeout=60s

# Step 2: Verify CRD registration
echo "[2/4] Verifying CRD..."
kubectl get crd mydatabases.database.example.com
echo "API resource registered:"
kubectl api-resources | grep mydatabase

# Step 3: Create operator namespace and deploy (if image is built)
echo "[3/4] Setting up operator namespace..."
kubectl create namespace mydatabase-operator-system --dry-run=client -o yaml | kubectl apply -f -

# Step 4: Create sample MyDatabase resources
echo "[4/4] Creating sample MyDatabase resources..."
kubectl apply -f "${PROJECT_DIR}/config/samples/mydatabase-sample.yaml"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "MyDatabase resources:"
kubectl get mydatabases
echo ""
echo "To run the operator locally:"
echo "  cd mydatabase-operator && make run"
echo ""
echo "To build and deploy the operator:"
echo "  make docker-build IMG=mydatabase-operator:v0.1.0"
echo "  make deploy IMG=mydatabase-operator:v0.1.0"
