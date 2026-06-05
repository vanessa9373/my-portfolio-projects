#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=== Deploying Multi-Cluster Management Lab ==="

# Step 1: Install Fleet
echo "[1/5] Installing Rancher Fleet..."
helm repo add fleet https://rancher.github.io/fleet-helm-charts/ 2>/dev/null || true
helm repo update

if ! kubectl get namespace cattle-fleet-system &>/dev/null; then
  helm install fleet-crd fleet/fleet-crd \
    --namespace cattle-fleet-system \
    --create-namespace \
    --wait

  helm install fleet fleet/fleet \
    --namespace cattle-fleet-system \
    --wait
else
  echo "Fleet already installed."
fi

kubectl get pods -n cattle-fleet-system

# Step 2: Create Fleet cluster groups
echo "[2/5] Creating cluster groups..."
kubectl create namespace fleet-default --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${MANIFESTS_DIR}/fleet-cluster-group.yaml"

# Step 3: Apply Fleet GitRepo
echo "[3/5] Applying Fleet GitRepo resources..."
kubectl apply -f "${MANIFESTS_DIR}/fleet-gitrepo.yaml"

# Step 4: Deploy monitoring namespace
echo "[4/5] Setting up monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Step 5: Apply Thanos configuration
echo "[5/5] Applying Thanos configuration..."
kubectl apply -f "${MANIFESTS_DIR}/thanos-values.yaml"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Fleet status:"
kubectl get clusters.fleet.cattle.io -n fleet-default 2>/dev/null || echo "  No clusters registered yet"
echo ""
echo "GitRepos:"
kubectl get gitrepo -n fleet-default 2>/dev/null || echo "  No GitRepos found"
echo ""
echo "ClusterGroups:"
kubectl get clustergroups -n fleet-default
echo ""
echo "Next steps:"
echo "  1. Register spoke clusters: ${SCRIPT_DIR}/register-cluster.sh <name> <region> <environment>"
echo "  2. Install Submariner: subctl deploy-broker && subctl join broker-info.subm"
echo "  3. Install Thanos: helm install thanos bitnami/thanos -n monitoring -f ${MANIFESTS_DIR}/thanos-values.yaml"
echo "  4. Provision new cluster: kubectl apply -f ${MANIFESTS_DIR}/cluster-api-cluster.yaml"
