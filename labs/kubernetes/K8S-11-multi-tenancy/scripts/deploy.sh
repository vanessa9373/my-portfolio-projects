#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"
POLICIES_DIR="${SCRIPT_DIR}/../policies"

echo "=== Deploying Multi-Tenancy Lab ==="

# Step 1: Create tenant namespaces
echo "[1/6] Creating tenant namespaces..."
kubectl apply -f "${MANIFESTS_DIR}/tenant-namespace.yaml"
kubectl get namespaces -l tenant=true

# Step 2: Apply NetworkPolicies
echo "[2/6] Applying network isolation policies..."
kubectl apply -f "${MANIFESTS_DIR}/tenant-networkpolicy.yaml"

# Step 3: Apply ResourceQuotas and LimitRanges
echo "[3/6] Applying resource quotas..."
kubectl apply -f "${MANIFESTS_DIR}/tenant-resourcequota.yaml"

# Step 4: Install Kyverno
echo "[4/6] Installing Kyverno..."
if ! kubectl get namespace kyverno &>/dev/null; then
  helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
  helm repo update
  helm install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    --set replicaCount=3 \
    --wait --timeout 300s
else
  echo "Kyverno already installed."
fi

# Step 5: Apply Kyverno policies
echo "[5/6] Applying Kyverno policies..."
kubectl apply -f "${POLICIES_DIR}/kyverno-require-labels.yaml"
kubectl apply -f "${POLICIES_DIR}/kyverno-restrict-registries.yaml"
kubectl apply -f "${POLICIES_DIR}/kyverno-limit-resources.yaml"

# Step 6: Verify
echo "[6/6] Verifying deployment..."
echo ""
echo "Tenant namespaces:"
kubectl get namespaces -l tenant=true
echo ""
echo "NetworkPolicies:"
kubectl get networkpolicies -A | grep -E "team-|NAMESPACE"
echo ""
echo "ResourceQuotas:"
kubectl get resourcequotas -A | grep -E "tenant-|NAMESPACE"
echo ""
echo "Kyverno policies:"
kubectl get clusterpolicies

echo ""
echo "=== Multi-Tenancy Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  - Create vCluster:    vcluster create team-echo -n team-echo-vcluster -f ${MANIFESTS_DIR}/vcluster-values.yaml"
echo "  - Onboard new tenant: ${SCRIPT_DIR}/create-tenant.sh <team-name> <cost-center>"
