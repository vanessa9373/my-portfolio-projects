#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-15: Platform Engineering Cleanup"
echo "============================================="

echo ""
echo "WARNING: This will delete all platform components"
echo "  including any infrastructure provisioned via Crossplane."
echo ""
read -p "Are you sure? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Delete claims first (triggers cloud resource deletion)
echo ""
echo "[1/5] Deleting database claims (triggers cloud resource cleanup)..."
kubectl delete -f "$PROJECT_DIR/crossplane/claim-database.yaml" --ignore-not-found=true 2>/dev/null || true

echo "  Waiting for cloud resources to be deleted..."
sleep 30

# Delete Composition and XRD
echo ""
echo "[2/5] Deleting Compositions and XRDs..."
kubectl delete -f "$PROJECT_DIR/crossplane/composition-aws-rds.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$PROJECT_DIR/crossplane/xrd-database.yaml" --ignore-not-found=true 2>/dev/null || true

# Delete AWS Provider
echo ""
echo "[3/5] Deleting Crossplane AWS Provider..."
kubectl delete -f "$PROJECT_DIR/crossplane/provider-aws.yaml" --ignore-not-found=true 2>/dev/null || true

# Uninstall Crossplane
echo ""
echo "[4/5] Uninstalling Crossplane..."
helm uninstall crossplane -n crossplane-system 2>/dev/null || true
kubectl delete namespace crossplane-system --ignore-not-found=true 2>/dev/null || true

# Delete Backstage
echo ""
echo "[5/5] Deleting Backstage..."
kubectl delete -f "$PROJECT_DIR/manifests/backstage-deployment.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace backstage --ignore-not-found=true 2>/dev/null || true

echo ""
echo "============================================="
echo " Cleanup complete!"
echo "============================================="
