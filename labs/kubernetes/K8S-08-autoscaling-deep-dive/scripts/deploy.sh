#!/bin/bash
set -e

echo "========================================="
echo "K8S-08: Deploying Autoscaling Components"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/6] Deploying scalable application..."
kubectl apply -f "${MANIFESTS_DIR}/deployment-scalable.yaml"
kubectl rollout status deployment/myapp --timeout=120s

echo ""
echo "[2/6] Configuring HPA v2 (CPU, memory, custom metrics)..."
kubectl apply -f "${MANIFESTS_DIR}/hpa-v2.yaml"

echo ""
echo "[3/6] Deploying VPA in recommendation mode..."
kubectl apply -f "${MANIFESTS_DIR}/vpa.yaml" 2>/dev/null || \
  echo "  [INFO] VPA CRDs may not be installed. Install VPA operator first."

echo ""
echo "[4/6] Deploying Prometheus Adapter..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${MANIFESTS_DIR}/prometheus-adapter-config.yaml" 2>/dev/null || \
  echo "  [INFO] Prometheus Adapter deployment requires TLS cert secret."

echo ""
echo "[5/6] Configuring Karpenter NodePool..."
kubectl apply -f "${MANIFESTS_DIR}/karpenter-nodepool.yaml" 2>/dev/null || \
  echo "  [INFO] Karpenter CRDs may not be installed. Install Karpenter first."

echo ""
echo "[6/6] Deploying KEDA ScaledObject..."
kubectl apply -f "${MANIFESTS_DIR}/keda-scaledobject.yaml" 2>/dev/null || \
  echo "  [INFO] KEDA CRDs may not be installed. Install KEDA first."

echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo ""
echo "HPA status:"
kubectl get hpa myapp-hpa
echo ""
echo "Current pods:"
kubectl get pods -l app=myapp
echo ""
echo "Next steps:"
echo "  1. Wait 5 minutes for VPA to collect metrics"
echo "  2. Run load test: ./scripts/load-test.sh"
echo "  3. Watch scaling: watch -n5 'kubectl get hpa && kubectl get pods'"
