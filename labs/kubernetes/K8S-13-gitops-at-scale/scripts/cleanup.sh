#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

echo "=== Cleaning Up GitOps at Scale Lab ==="

# Remove ApplicationSets (this also deletes generated Applications)
echo "[1/5] Removing ApplicationSets..."
kubectl delete -f "${PROJECT_DIR}/manifests/applicationset-list.yaml" --ignore-not-found
kubectl delete -f "${PROJECT_DIR}/manifests/applicationset-git.yaml" --ignore-not-found

# Remove Image Updater config
echo "[2/5] Removing Image Updater configuration..."
kubectl delete -f "${PROJECT_DIR}/manifests/image-updater-config.yaml" --ignore-not-found

# Remove Kustomize deployments
echo "[3/5] Removing Kustomize deployments..."
for ENV in dev staging prod; do
  kubectl kustomize "${PROJECT_DIR}/overlays/${ENV}/" | kubectl delete -f - --ignore-not-found 2>/dev/null || true
done

# Remove namespaces
echo "[4/5] Removing namespaces..."
for NS in dev staging prod; do
  kubectl delete namespace "${NS}" --ignore-not-found
done

# Optionally remove ArgoCD
echo "[5/5] ArgoCD removal (optional)..."
read -p "Uninstall ArgoCD? (y/N): " UNINSTALL
if [[ "${UNINSTALL}" =~ ^[Yy]$ ]]; then
  kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found
  kubectl delete namespace argocd --ignore-not-found
  echo "ArgoCD uninstalled."
fi

echo ""
echo "=== Cleanup Complete ==="
