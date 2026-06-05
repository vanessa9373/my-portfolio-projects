#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-18: Performance Engineering & FinOps"
echo " Cilium + Kubecost + Right-Sizing + Spot"
echo "============================================="

# Check prerequisites
echo ""
echo "[1/8] Checking prerequisites..."
for cmd in kubectl helm cilium; do
  if command -v "$cmd" &> /dev/null; then
    echo "  $cmd: found"
  else
    echo "  $cmd: NOT FOUND"
  fi
done

# Verify cluster connection
if ! kubectl get nodes &> /dev/null; then
  echo "ERROR: Cannot connect to Kubernetes cluster."
  exit 1
fi
echo "  Cluster nodes:"
kubectl get nodes --no-headers | sed 's/^/    /'

# Install Cilium
echo ""
echo "[2/8] Installing Cilium with eBPF..."
"$SCRIPT_DIR/install-cilium.sh"

# Deploy Kubecost
echo ""
echo "[3/8] Deploying Kubecost..."
helm repo add kubecost https://kubecost.github.io/cost-analyzer/ 2>/dev/null || true
helm repo update

kubectl create namespace kubecost --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --values "$PROJECT_DIR/manifests/kubecost-values.yaml" \
  --wait --timeout 300s 2>/dev/null || \
  echo "  WARNING: Kubecost installation may require additional configuration"

# Configure cost allocation labels
echo ""
echo "[4/8] Configuring cost allocation labels..."
for ns in production staging monitoring batch-jobs ci-cd; do
  if kubectl get namespace "$ns" &>/dev/null; then
    kubectl label namespace "$ns" cost-center="$ns" --overwrite 2>/dev/null || true
    echo "  Labeled namespace: $ns"
  fi
done

# Install VPA
echo ""
echo "[5/8] Installing Vertical Pod Autoscaler..."
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vertical-pod-autoscaler.yaml 2>/dev/null || \
  echo "  WARNING: VPA installation may require manual download"

# Apply VPA recommendation objects
echo ""
echo "[6/8] Applying VPA recommendations..."
kubectl apply -f "$PROJECT_DIR/manifests/vpa-recommendations.yaml" 2>/dev/null || \
  echo "  WARNING: Some VPA objects may require target deployments to exist"

# Deploy bin-packing scheduler
echo ""
echo "[7/8] Deploying bin-packing scheduler..."
kubectl apply -f "$PROJECT_DIR/manifests/bin-packing-scheduler.yaml"

echo "  Waiting for bin-packing scheduler to be ready..."
kubectl wait --for=condition=available deployment/bin-packing-scheduler \
  -n kube-system --timeout=120s 2>/dev/null || echo "  Scheduler starting..."

# Apply spot node pool
echo ""
echo "[8/8] Applying spot node pool configuration..."
kubectl apply -f "$PROJECT_DIR/manifests/spot-nodepool.yaml" 2>/dev/null || \
  echo "  NOTE: Karpenter CRDs required for spot node pool"

# Verification
echo ""
echo "============================================="
echo " Deployment Verification"
echo "============================================="
echo ""
echo "  Cilium Status:"
cilium status 2>/dev/null | head -5 | sed 's/^/    /' || echo "    Cilium CLI not available"
echo ""
echo "  Kubecost Pods:"
kubectl get pods -n kubecost --no-headers 2>/dev/null | sed 's/^/    /' || echo "    Not deployed"
echo ""
echo "  VPA Objects:"
kubectl get vpa -A --no-headers 2>/dev/null | sed 's/^/    /' || echo "    Not deployed"
echo ""
echo "  Bin-Packing Scheduler:"
kubectl get pods -n kube-system -l component=bin-packing-scheduler --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Node Pools:"
kubectl get nodepools --no-headers 2>/dev/null | sed 's/^/    /' || echo "    Karpenter not available"

echo ""
echo "============================================="
echo " Deployment complete!"
echo ""
echo " Kubecost Dashboard: http://kubecost.local:9090"
echo " Hubble UI: http://hubble.local"
echo ""
echo " Run cost-report.sh for optimization analysis"
echo "============================================="
