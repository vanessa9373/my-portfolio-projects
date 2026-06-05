#!/bin/bash
set -e

echo "=== Installing Istio Service Mesh ==="

ISTIO_VERSION="1.20.0"

# Download Istio
echo "[1/5] Downloading Istio ${ISTIO_VERSION}..."
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
export PATH=$PWD/istio-${ISTIO_VERSION}/bin:$PATH

# Pre-flight check
echo "[2/5] Running pre-flight checks..."
istioctl x precheck

# Install Istio with demo profile
echo "[3/5] Installing Istio with demo profile..."
istioctl install --set profile=demo -y

# Wait for Istio pods to be ready
echo "[4/5] Waiting for Istio control plane..."
kubectl wait --for=condition=ready pod -l app=istiod -n istio-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=istio-ingressgateway -n istio-system --timeout=300s

# Install addons (Kiali, Jaeger, Prometheus, Grafana)
echo "[5/5] Installing observability addons..."
kubectl apply -f istio-${ISTIO_VERSION}/samples/addons/
kubectl wait --for=condition=ready pod -l app=kiali -n istio-system --timeout=300s

# Enable sidecar injection on default namespace
kubectl label namespace default istio-injection=enabled --overwrite

echo ""
echo "=== Istio Installation Complete ==="
echo "Control plane: $(istioctl version --short)"
echo "Sidecar injection: enabled on 'default' namespace"
echo ""
echo "Dashboards:"
echo "  Kiali:      istioctl dashboard kiali"
echo "  Jaeger:     istioctl dashboard jaeger"
echo "  Grafana:    istioctl dashboard grafana"
echo "  Prometheus: istioctl dashboard prometheus"
