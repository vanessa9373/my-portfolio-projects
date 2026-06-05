#!/bin/bash
set -e

echo "============================================"
echo "  K8S-03: Ingress Controllers — Deploy All"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/8] Installing NGINX Ingress Controller via Helm..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values "${MANIFESTS_DIR}/nginx-ingress-values.yaml" \
  --wait --timeout 120s

echo ""
echo "[2/8] Creating application namespace..."
kubectl create namespace k8s-ingress --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[3/8] Deploying microservices (app, api, admin)..."
kubectl apply -f "${MANIFESTS_DIR}/app-deployment.yaml"
kubectl apply -f "${MANIFESTS_DIR}/api-deployment.yaml"
kubectl apply -f "${MANIFESTS_DIR}/admin-deployment.yaml"

echo ""
echo "[4/8] Creating ClusterIP Services..."
kubectl apply -f "${MANIFESTS_DIR}/services.yaml"

echo ""
echo "[5/8] Creating path-based Ingress routing..."
kubectl apply -f "${MANIFESTS_DIR}/ingress-path.yaml"

echo ""
echo "[6/8] Creating host-based Ingress routing..."
kubectl apply -f "${MANIFESTS_DIR}/ingress-host.yaml"

echo ""
echo "[7/8] Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait --timeout 120s

echo ""
echo "[8/8] Creating ClusterIssuer and TLS Ingress..."
kubectl apply -f "${MANIFESTS_DIR}/cert-manager-issuer.yaml"
kubectl apply -f "${MANIFESTS_DIR}/ingress-tls.yaml"

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "--- Ingress Controller ---"
kubectl get svc -n ingress-nginx
echo ""
echo "--- Deployments ---"
kubectl get deployments -n k8s-ingress
echo ""
echo "--- Services ---"
kubectl get svc -n k8s-ingress
echo ""
echo "--- Ingress Rules ---"
kubectl get ingress -n k8s-ingress
echo ""

INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "<pending>")
echo "Ingress Controller IP: ${INGRESS_IP}"
echo ""
echo "Test commands:"
echo "  curl -H 'Host: myapp.example.com' http://${INGRESS_IP}/app"
echo "  curl -H 'Host: app.example.com' http://${INGRESS_IP}/"
echo ""
