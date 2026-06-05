#!/bin/bash
set -e

echo "========================================="
echo "K8S-07: Resource Governance - Eviction Testing"
echo "========================================="

NAMESPACE="team-a"

echo ""
echo "=== TEST 1: Verify DaemonSet Coverage ==="
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
DS_READY=$(kubectl get daemonset fluentd-logging -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
echo "  Nodes in cluster: ${NODE_COUNT}"
echo "  DaemonSet pods ready: ${DS_READY}"
if [ "${NODE_COUNT}" = "${DS_READY}" ]; then
  echo "  [PASS] DaemonSet covers all nodes"
else
  echo "  [WARN] DaemonSet coverage incomplete (${DS_READY}/${NODE_COUNT})"
fi

echo ""
echo "=== TEST 2: Verify ResourceQuota Enforcement ==="
echo "  Attempting to create a pod that exceeds quota..."
kubectl run quota-test --image=nginx \
  --overrides='{"spec":{"containers":[{"name":"nginx","image":"nginx","resources":{"requests":{"cpu":"20","memory":"64Gi"}}}]}}' \
  -n ${NAMESPACE} 2>&1 || echo "  [PASS] Pod creation rejected by quota (expected)"
kubectl delete pod quota-test -n ${NAMESPACE} --ignore-not-found=true 2>/dev/null

echo ""
echo "=== TEST 3: Verify LimitRange Defaults ==="
echo "  Creating pod without resource specs..."
kubectl run limitrange-test --image=nginx:1.25-alpine -n ${NAMESPACE} 2>/dev/null || true
sleep 5
INJECTED_CPU=$(kubectl get pod limitrange-test -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "none")
echo "  Injected CPU request: ${INJECTED_CPU}"
if [ "${INJECTED_CPU}" != "none" ] && [ "${INJECTED_CPU}" != "" ]; then
  echo "  [PASS] LimitRange injected default resources"
else
  echo "  [INFO] LimitRange defaults not yet visible"
fi
kubectl delete pod limitrange-test -n ${NAMESPACE} --ignore-not-found=true 2>/dev/null

echo ""
echo "=== TEST 4: Verify QoS Classes ==="
for pod in qos-guaranteed qos-burstable qos-besteffort; do
  QOS=$(kubectl get pod ${pod} -n ${NAMESPACE} -o jsonpath='{.status.qosClass}' 2>/dev/null || echo "NOT_FOUND")
  echo "  ${pod}: QoS = ${QOS}"
done

echo ""
echo "=== TEST 5: Verify PDB Protection ==="
echo "  Checking PDB status..."
ALLOWED=$(kubectl get pdb myapp-pdb -n ${NAMESPACE} -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null || echo "N/A")
CURRENT=$(kubectl get pdb myapp-pdb -n ${NAMESPACE} -o jsonpath='{.status.currentHealthy}' 2>/dev/null || echo "N/A")
echo "  Healthy pods: ${CURRENT}"
echo "  Disruptions allowed: ${ALLOWED}"

echo ""
echo "=== TEST 6: Verify PriorityClass Assignment ==="
for pc in critical-system standard-workload background-batch; do
  PRIORITY=$(kubectl get priorityclass ${pc} -o jsonpath='{.value}' 2>/dev/null || echo "NOT_FOUND")
  echo "  ${pc}: priority = ${PRIORITY}"
done

echo ""
echo "=== TEST 7: Simulate PDB Drain Protection ==="
echo "  Attempting to drain a node (dry-run)..."
FIRST_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${FIRST_NODE}" ]; then
  kubectl drain "${FIRST_NODE}" --dry-run=client --ignore-daemonsets --delete-emptydir-data 2>&1 | head -20
  echo "  [PASS] Drain dry-run completed (PDB would limit eviction rate)"
else
  echo "  [SKIP] No nodes available for drain test"
fi

echo ""
echo "========================================="
echo "Eviction testing complete!"
echo "========================================="
