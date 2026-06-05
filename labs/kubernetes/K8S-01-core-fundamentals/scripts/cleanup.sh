#!/bin/bash
set -e

echo "============================================"
echo "  K8S-01: Core Fundamentals — Cleanup"
echo "============================================"

echo ""
echo "This will delete the entire k8s-fundamentals namespace"
echo "and ALL resources within it (pods, services, configmaps, secrets)."
echo ""

read -p "Are you sure? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Deleting namespace k8s-fundamentals..."
kubectl delete namespace k8s-fundamentals --timeout=60s

echo ""
echo "Resetting context to default namespace..."
kubectl config set-context --current --namespace=default

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "Verify: kubectl get namespaces"
echo ""
