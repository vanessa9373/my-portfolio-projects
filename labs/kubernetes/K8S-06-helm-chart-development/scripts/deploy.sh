#!/bin/bash
set -e

echo "========================================="
echo "K8S-06: Helm Chart Deployment"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../charts/myapp"

# Default to dev environment if not specified
ENVIRONMENT="${1:-dev}"

echo ""
echo "Environment: ${ENVIRONMENT}"
echo "Chart path:  ${CHART_DIR}"
echo ""

# Validate environment
case "${ENVIRONMENT}" in
  dev|staging|prod)
    VALUES_FILE="${CHART_DIR}/values-${ENVIRONMENT}.yaml"
    ;;
  *)
    echo "ERROR: Unknown environment '${ENVIRONMENT}'"
    echo "Usage: $0 [dev|staging|prod]"
    exit 1
    ;;
esac

if [ ! -f "${VALUES_FILE}" ]; then
  echo "ERROR: Values file not found: ${VALUES_FILE}"
  exit 1
fi

echo "[1/4] Linting chart..."
helm lint "${CHART_DIR}" -f "${VALUES_FILE}"
echo "  Lint passed."

echo ""
echo "[2/4] Updating dependencies..."
helm dependency update "${CHART_DIR}"

echo ""
echo "[3/4] Rendering templates (dry run)..."
helm template myapp "${CHART_DIR}" -f "${VALUES_FILE}" > /dev/null
echo "  Templates render successfully."

echo ""
echo "[4/4] Installing/upgrading release..."
helm upgrade --install myapp "${CHART_DIR}" \
  -f "${VALUES_FILE}" \
  --namespace "myapp-${ENVIRONMENT}" \
  --create-namespace \
  --wait \
  --timeout 300s

echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo ""
echo "Release status:"
helm status myapp -n "myapp-${ENVIRONMENT}"
echo ""
echo "Run tests with: helm test myapp -n myapp-${ENVIRONMENT}"
