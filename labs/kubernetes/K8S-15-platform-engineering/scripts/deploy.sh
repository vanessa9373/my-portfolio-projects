#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-15: Platform Engineering Deployment"
echo " Backstage + Crossplane Developer Platform"
echo "============================================="

# Check prerequisites
echo ""
echo "[1/6] Checking prerequisites..."
for cmd in kubectl helm curl; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is required but not installed."
    exit 1
  fi
done
echo "  All prerequisites met."

# Install Crossplane
echo ""
echo "[2/6] Installing Crossplane..."
"$SCRIPT_DIR/install-crossplane.sh"

# Install AWS Provider
echo ""
echo "[3/6] Configuring AWS Provider for Crossplane..."
kubectl apply -f "$PROJECT_DIR/crossplane/provider-aws.yaml"

echo "  Waiting for AWS provider to become healthy..."
kubectl wait --for=condition=healthy provider.pkg.crossplane.io/provider-aws \
  --timeout=300s 2>/dev/null || echo "  Provider still initializing (may take a few minutes)"

# Apply XRD and Composition
echo ""
echo "[4/6] Creating Platform APIs (XRD + Composition)..."
kubectl apply -f "$PROJECT_DIR/crossplane/xrd-database.yaml"
echo "  Waiting for XRD to be established..."
sleep 10
kubectl apply -f "$PROJECT_DIR/crossplane/composition-aws-rds.yaml"
echo "  Database platform API is ready."

# Deploy Backstage
echo ""
echo "[5/6] Deploying Backstage Developer Portal..."
kubectl apply -f "$PROJECT_DIR/manifests/backstage-deployment.yaml"

echo "  Waiting for Backstage to be ready..."
kubectl wait --for=condition=available deployment/backstage \
  -n backstage --timeout=300s 2>/dev/null || echo "  Backstage still starting..."

# Verify deployment
echo ""
echo "[6/6] Verifying deployment..."
echo ""
echo "  Crossplane pods:"
kubectl get pods -n crossplane-system --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Backstage pods:"
kubectl get pods -n backstage --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Platform APIs (XRDs):"
kubectl get xrd --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Compositions:"
kubectl get composition --no-headers 2>/dev/null | sed 's/^/    /'

echo ""
echo "============================================="
echo " Deployment complete!"
echo ""
echo " Backstage Portal: http://backstage.local:7007"
echo " To test self-service:"
echo "   kubectl apply -f crossplane/claim-database.yaml"
echo "============================================="
