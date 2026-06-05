#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

echo "=== Deploying GitOps at Scale Lab ==="

# Step 1: Verify Kustomize builds
echo "[1/6] Validating Kustomize overlays..."
for ENV in dev staging prod; do
  echo "  Building ${ENV}..."
  kubectl kustomize "${PROJECT_DIR}/overlays/${ENV}/" > /dev/null
  echo "  ${ENV}: OK"
done

# Step 2: Create namespaces
echo "[2/6] Creating namespaces..."
for NS in dev staging prod; do
  kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -
done

# Step 3: Deploy to dev with Kustomize (manual, before ArgoCD)
echo "[3/6] Deploying to dev namespace..."
kubectl kustomize "${PROJECT_DIR}/overlays/dev/" | kubectl apply -f -
kubectl wait --for=condition=available deployment/myapp -n dev --timeout=120s

# Step 4: Install ArgoCD
echo "[4/6] Installing ArgoCD..."
if ! kubectl get namespace argocd &>/dev/null; then
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
fi

# Step 5: Apply ApplicationSets
echo "[5/6] Applying ApplicationSets..."
kubectl apply -f "${PROJECT_DIR}/manifests/applicationset-list.yaml"
kubectl apply -f "${PROJECT_DIR}/manifests/applicationset-git.yaml"

# Step 6: Apply Image Updater config
echo "[6/6] Configuring Image Updater..."
kubectl apply -f "${PROJECT_DIR}/manifests/image-updater-config.yaml"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "ArgoCD Applications:"
kubectl get applications -n argocd 2>/dev/null || echo "  (waiting for sync)"
echo ""
echo "Kustomize builds:"
for ENV in dev staging prod; do
  REPLICAS=$(kubectl kustomize "${PROJECT_DIR}/overlays/${ENV}/" | grep "replicas:" | head -1 | awk '{print $2}')
  echo "  ${ENV}: ${REPLICAS} replicas"
done
echo ""
echo "Access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
