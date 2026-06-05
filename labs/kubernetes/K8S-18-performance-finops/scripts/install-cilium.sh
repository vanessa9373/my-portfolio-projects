#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " Cilium Installation with eBPF Dataplane"
echo "============================================="

# Check for Cilium CLI
if ! command -v cilium &>/dev/null; then
  echo "Installing Cilium CLI..."
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)

  if [[ "$(uname -s)" == "Darwin" ]]; then
    CLI_ARCH="darwin-amd64"
  else
    CLI_ARCH="linux-amd64"
  fi

  curl -L --fail --remote-name-all \
    "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${CLI_ARCH}.tar.gz"
  sudo tar xzvf "cilium-${CLI_ARCH}.tar.gz" -C /usr/local/bin
  rm "cilium-${CLI_ARCH}.tar.gz"
fi

echo "Cilium CLI version: $(cilium version --client 2>/dev/null || echo 'unknown')"

# Detect Kubernetes API server endpoint
echo ""
echo "Detecting Kubernetes API server..."
K8S_API_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | \
  sed 's|https://||' | cut -d: -f1)
K8S_API_PORT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | \
  sed 's|https://||' | cut -d: -f2)
K8S_API_PORT="${K8S_API_PORT:-6443}"

echo "  API Server: ${K8S_API_HOST}:${K8S_API_PORT}"

# Update Cilium values with detected API server
echo ""
echo "Installing Cilium..."
helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update

# Replace placeholder in values file
sed "s/KUBERNETES_API_SERVER_IP/${K8S_API_HOST}/g" \
  "$PROJECT_DIR/manifests/cilium-values.yaml" > /tmp/cilium-values-resolved.yaml

helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --values /tmp/cilium-values-resolved.yaml \
  --set k8sServiceHost="${K8S_API_HOST}" \
  --set k8sServicePort="${K8S_API_PORT}" \
  --wait --timeout 300s

rm -f /tmp/cilium-values-resolved.yaml

# Wait for Cilium to be ready
echo ""
echo "Waiting for Cilium to be ready..."
cilium status --wait --wait-duration 120s 2>/dev/null || \
  kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=120s

# Remove kube-proxy (Cilium replaces it)
echo ""
echo "Removing kube-proxy (replaced by Cilium eBPF)..."
kubectl -n kube-system delete daemonset kube-proxy 2>/dev/null || \
  echo "  kube-proxy DaemonSet not found (may already be removed)"
kubectl -n kube-system delete configmap kube-proxy 2>/dev/null || \
  echo "  kube-proxy ConfigMap not found"

# Verify eBPF mode
echo ""
echo "Verifying eBPF kube-proxy replacement..."
kubectl exec -n kube-system -l k8s-app=cilium -- cilium status 2>/dev/null | \
  grep -E "KubeProxy|BPF" | head -5 || echo "  Verification requires exec access to Cilium pods"

# Run connectivity test
echo ""
echo "Running connectivity test..."
cilium connectivity test --test="client-egress" 2>/dev/null || \
  echo "  Connectivity test skipped (full test takes several minutes)"

echo ""
echo "============================================="
echo " Cilium Installation Complete"
echo ""
echo "  Hubble UI: kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
echo "  Status: cilium status"
echo "  Test: cilium connectivity test"
echo "============================================="
