#!/bin/bash
set -e

echo "========================================="
echo "K8S-06: Helm Chart Cleanup"
echo "========================================="

ENVIRONMENT="${1:-dev}"

echo ""
echo "Environment: ${ENVIRONMENT}"
echo ""

echo "[1/3] Uninstalling Helm release..."
helm uninstall myapp -n "myapp-${ENVIRONMENT}" --wait 2>/dev/null || \
  echo "  Release 'myapp' not found in namespace myapp-${ENVIRONMENT}. Skipping."

echo ""
echo "[2/3] Cleaning up PVCs..."
kubectl delete pvc --all -n "myapp-${ENVIRONMENT}" --ignore-not-found=true

echo ""
echo "[3/3] Deleting namespace..."
kubectl delete namespace "myapp-${ENVIRONMENT}" --ignore-not-found=true

echo ""
echo "========================================="
echo "Cleanup complete!"
echo "========================================="
echo ""
echo "To clean up all environments:"
echo "  $0 dev && $0 staging && $0 prod"
