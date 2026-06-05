#!/bin/bash
set -e

echo "============================================"
echo "  K8S-02: Persistent Storage — Cleanup"
echo "============================================"

echo ""
echo "This will delete:"
echo "  - Namespace: k8s-storage (all pods, PVCs, services)"
echo "  - StorageClasses: fast-storage, economy-storage"
echo "  - PersistentVolume: static-pv-10gi"
echo ""

read -p "Are you sure? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "[1/3] Deleting namespace (cascades to PVCs and pods)..."
kubectl delete namespace k8s-storage --timeout=60s || true

echo ""
echo "[2/3] Deleting StorageClasses..."
kubectl delete storageclass fast-storage economy-storage --ignore-not-found=true

echo ""
echo "[3/3] Deleting static PersistentVolume..."
kubectl delete pv static-pv-10gi --ignore-not-found=true

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "Verify:"
echo "  kubectl get pv"
echo "  kubectl get storageclass"
echo "  kubectl get namespaces"
echo ""
