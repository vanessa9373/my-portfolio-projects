#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=== Deploying Service Mesh Lab ==="

# Step 1: Verify Istio is installed
echo "[1/6] Verifying Istio installation..."
if ! kubectl get namespace istio-system &>/dev/null; then
  echo "Istio not found. Run install-istio.sh first."
  exit 1
fi
echo "Istio control plane: $(istioctl version --short 2>/dev/null || echo 'istioctl not in PATH')"

# Step 2: Ensure sidecar injection is enabled
echo "[2/6] Enabling sidecar injection..."
kubectl label namespace default istio-injection=enabled --overwrite

# Step 3: Deploy sample application
echo "[3/6] Deploying sample microservices..."
kubectl apply -f "${MANIFESTS_DIR}/sample-app-deployment.yaml"
kubectl wait --for=condition=ready pod -l app=frontend --timeout=120s
kubectl wait --for=condition=ready pod -l app=backend --timeout=120s
kubectl wait --for=condition=ready pod -l app=database --timeout=120s

# Step 4: Apply mTLS policy
echo "[4/6] Applying strict mTLS policy..."
kubectl apply -f "${MANIFESTS_DIR}/istio-peer-authentication.yaml"

# Step 5: Apply gateway and routing
echo "[5/6] Configuring ingress gateway..."
kubectl apply -f "${MANIFESTS_DIR}/gateway.yaml"

# Step 6: Apply canary traffic splitting
echo "[6/6] Configuring canary traffic split (90/10)..."
kubectl apply -f "${MANIFESTS_DIR}/virtualservice-canary.yaml"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Pods:"
kubectl get pods -o wide
echo ""
echo "Services:"
kubectl get svc
echo ""
echo "Istio config:"
kubectl get virtualservices,destinationrules,peerauthentications
echo ""
echo "Next steps:"
echo "  - Apply fault injection:    kubectl apply -f ${MANIFESTS_DIR}/fault-injection.yaml"
echo "  - Apply circuit breaking:   kubectl apply -f ${MANIFESTS_DIR}/destinationrule-circuit-breaker.yaml"
echo "  - Open Kiali dashboard:     istioctl dashboard kiali"
echo "  - Open Jaeger tracing:      istioctl dashboard jaeger"
