#!/bin/bash
set -e

echo "========================================="
echo "K8S-08: Cleaning Up Autoscaling Resources"
echo "========================================="

echo ""
echo "[1/6] Deleting KEDA ScaledObject and worker..."
kubectl delete scaledobject worker-scaler --ignore-not-found=true
kubectl delete triggerauthentication aws-credentials --ignore-not-found=true
kubectl delete deployment worker --ignore-not-found=true
kubectl delete serviceaccount worker-sa --ignore-not-found=true

echo ""
echo "[2/6] Deleting Karpenter NodePool..."
kubectl delete nodepool default --ignore-not-found=true 2>/dev/null || true
kubectl delete ec2nodeclass default --ignore-not-found=true 2>/dev/null || true

echo ""
echo "[3/6] Deleting VPA resources..."
kubectl delete vpa myapp-vpa --ignore-not-found=true 2>/dev/null || true
kubectl delete vpa worker-vpa --ignore-not-found=true 2>/dev/null || true

echo ""
echo "[4/6] Deleting HPA..."
kubectl delete hpa myapp-hpa --ignore-not-found=true

echo ""
echo "[5/6] Deleting Prometheus Adapter..."
kubectl delete deployment prometheus-adapter -n monitoring --ignore-not-found=true
kubectl delete configmap prometheus-adapter-config -n monitoring --ignore-not-found=true

echo ""
echo "[6/6] Deleting application..."
kubectl delete deployment myapp --ignore-not-found=true
kubectl delete service myapp --ignore-not-found=true

echo ""
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app=myapp --timeout=60s 2>/dev/null || true
kubectl wait --for=delete pod -l app=worker --timeout=60s 2>/dev/null || true

echo ""
echo "========================================="
echo "Cleanup complete!"
echo "========================================="
echo ""
echo "Remaining resources:"
kubectl get hpa,vpa,scaledobject 2>/dev/null || echo "  None"
