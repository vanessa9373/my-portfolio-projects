#!/bin/bash
set -e

echo "============================================"
echo "  K8S-03: Ingress Controllers — Cleanup"
echo "============================================"

echo ""
echo "This will delete:"
echo "  - Namespace: k8s-ingress (all apps, services, ingress rules)"
echo "  - NGINX Ingress Controller (Helm release)"
echo "  - cert-manager (Helm release)"
echo "  - ClusterIssuers"
echo ""

read -p "Are you sure? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "[1/5] Deleting application namespace..."
kubectl delete namespace k8s-ingress --timeout=60s || true

echo ""
echo "[2/5] Deleting ClusterIssuers..."
kubectl delete clusterissuer letsencrypt-staging letsencrypt-prod --ignore-not-found=true

echo ""
echo "[3/5] Uninstalling cert-manager..."
helm uninstall cert-manager -n cert-manager 2>/dev/null || true
kubectl delete namespace cert-manager --timeout=60s || true

echo ""
echo "[4/5] Uninstalling NGINX Ingress Controller..."
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
kubectl delete namespace ingress-nginx --timeout=60s || true

echo ""
echo "[5/5] Cleaning up CRDs..."
kubectl delete crd certificates.cert-manager.io certificaterequests.cert-manager.io \
  challenges.acme.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io \
  orders.acme.cert-manager.io --ignore-not-found=true 2>/dev/null || true

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "Verify:"
echo "  kubectl get namespaces"
echo "  helm list -A"
echo ""
