#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=== Cleaning Up Multi-Cluster Management Lab ==="

# Remove Cluster API clusters
echo "[1/6] Removing Cluster API resources..."
kubectl delete -f "${MANIFESTS_DIR}/cluster-api-cluster.yaml" --ignore-not-found
echo "Waiting for cluster deprovisioning (this may take several minutes)..."
kubectl wait --for=delete cluster/new-prod-ap --timeout=600s 2>/dev/null || true

# Remove Fleet GitRepos
echo "[2/6] Removing Fleet GitRepos..."
kubectl delete -f "${MANIFESTS_DIR}/fleet-gitrepo.yaml" --ignore-not-found

# Remove Fleet ClusterGroups
echo "[3/6] Removing Fleet ClusterGroups..."
kubectl delete -f "${MANIFESTS_DIR}/fleet-cluster-group.yaml" --ignore-not-found

# Remove Fleet Cluster registrations
echo "[4/6] Removing registered clusters..."
kubectl delete clusters.fleet.cattle.io --all -n fleet-default 2>/dev/null || true
kubectl delete clusterregistrationtokens --all -n fleet-default 2>/dev/null || true

# Remove Submariner
echo "[5/6] Removing Submariner..."
kubectl delete -f "${MANIFESTS_DIR}/submariner-broker.yaml" --ignore-not-found
kubectl delete namespace submariner-k8s-broker --ignore-not-found

# Optionally remove Fleet and Thanos
echo "[6/6] Optional component removal..."
read -p "Uninstall Fleet? (y/N): " UNINSTALL_FLEET
if [[ "${UNINSTALL_FLEET}" =~ ^[Yy]$ ]]; then
  helm uninstall fleet -n cattle-fleet-system 2>/dev/null || true
  helm uninstall fleet-crd -n cattle-fleet-system 2>/dev/null || true
  kubectl delete namespace cattle-fleet-system --ignore-not-found
  echo "Fleet uninstalled."
fi

read -p "Uninstall Thanos? (y/N): " UNINSTALL_THANOS
if [[ "${UNINSTALL_THANOS}" =~ ^[Yy]$ ]]; then
  helm uninstall thanos -n monitoring 2>/dev/null || true
  kubectl delete namespace monitoring --ignore-not-found
  echo "Thanos uninstalled."
fi

# Clean up fleet-default namespace
kubectl delete namespace fleet-default --ignore-not-found

echo ""
echo "=== Cleanup Complete ==="
