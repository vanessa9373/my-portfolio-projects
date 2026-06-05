#!/bin/bash
set -e

echo "========================================="
echo "K8S-08: Autoscaling Load Test"
echo "========================================="

# Configuration
TARGET_URL="${1:-http://myapp.default.svc.cluster.local}"
DURATION="${2:-120}"
CONCURRENCY="${3:-50}"
RPS="${4:-200}"

echo ""
echo "Configuration:"
echo "  Target URL:   ${TARGET_URL}"
echo "  Duration:     ${DURATION}s"
echo "  Concurrency:  ${CONCURRENCY}"
echo "  Target RPS:   ${RPS}"
echo ""

# Check if hey is installed
if ! command -v hey &> /dev/null; then
  echo "Installing 'hey' load testing tool..."
  # For Linux
  if [[ "$(uname)" == "Linux" ]]; then
    wget -q https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -O /tmp/hey
    chmod +x /tmp/hey
    HEY="/tmp/hey"
  # For macOS
  elif [[ "$(uname)" == "Darwin" ]]; then
    brew install hey 2>/dev/null || {
      echo "ERROR: Please install 'hey' first: brew install hey"
      exit 1
    }
    HEY="hey"
  fi
else
  HEY="hey"
fi

echo "=== Phase 1: Baseline (30s) ==="
echo "Capturing baseline metrics..."
echo "Current HPA state:"
kubectl get hpa myapp-hpa 2>/dev/null || echo "  HPA not found"
echo "Current pod count:"
kubectl get pods -l app=myapp --no-headers 2>/dev/null | wc -l | tr -d ' '
echo ""

echo "=== Phase 2: Ramp-Up Load (${DURATION}s) ==="
echo "Starting load test..."
${HEY} -z "${DURATION}s" -c "${CONCURRENCY}" -q "${RPS}" "${TARGET_URL}" &
LOAD_PID=$!

echo "Load test running (PID: ${LOAD_PID})..."
echo "Monitoring HPA every 15 seconds..."
echo ""

ELAPSED=0
while kill -0 ${LOAD_PID} 2>/dev/null; do
  ELAPSED=$((ELAPSED + 15))
  echo "--- T+${ELAPSED}s ---"
  kubectl get hpa myapp-hpa --no-headers 2>/dev/null || true
  POD_COUNT=$(kubectl get pods -l app=myapp --no-headers 2>/dev/null | wc -l | tr -d ' ')
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "  Pods: ${POD_COUNT} | Nodes: ${NODE_COUNT}"
  echo ""
  sleep 15
done

wait ${LOAD_PID} || true

echo ""
echo "=== Phase 3: Post-Load Analysis ==="
echo ""
echo "Final HPA state:"
kubectl get hpa myapp-hpa 2>/dev/null || echo "  HPA not found"
echo ""
echo "Final pod count:"
kubectl get pods -l app=myapp --no-headers 2>/dev/null | wc -l | tr -d ' '
echo ""
echo "HPA scaling events:"
kubectl describe hpa myapp-hpa 2>/dev/null | grep -A20 "Events:" || true
echo ""
echo "VPA recommendations:"
kubectl describe vpa myapp-vpa 2>/dev/null | grep -A15 "Recommendation:" || echo "  VPA not available"

echo ""
echo "========================================="
echo "Load test complete!"
echo "========================================="
echo ""
echo "Watch scale-down over the next 5 minutes:"
echo "  watch -n10 'kubectl get hpa myapp-hpa && kubectl get pods -l app=myapp'"
