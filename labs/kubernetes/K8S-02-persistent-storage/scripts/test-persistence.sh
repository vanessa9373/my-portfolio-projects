#!/bin/bash
set -e

echo "============================================"
echo "  K8S-02: Persistent Storage — Test Script"
echo "============================================"
echo ""
echo "This script proves data survives pod deletion."
echo ""

NAMESPACE="k8s-storage"

# --- Test 1: Static PVC Pod ---
echo "=== Test 1: Static PVC Persistence ==="
echo ""

echo "[1/4] Writing test data to storage-demo pod..."
kubectl exec storage-demo -n ${NAMESPACE} -- sh -c 'echo "PERSISTENCE_TEST: written at $(date)" > /data/persistence-test.txt'
kubectl exec storage-demo -n ${NAMESPACE} -- cat /data/persistence-test.txt
echo ""

echo "[2/4] Deleting the pod..."
kubectl delete pod storage-demo -n ${NAMESPACE} --wait=true
echo ""

echo "[3/4] Recreating the pod..."
kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/../manifests/pod-with-pv.yaml"
echo "Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/storage-demo -n ${NAMESPACE} --timeout=60s
echo ""

echo "[4/4] Verifying data survived pod deletion..."
echo "--- Data from before deletion: ---"
kubectl exec storage-demo -n ${NAMESPACE} -- cat /data/persistence-test.txt
echo ""

# --- Test 2: Dynamic PVC Deployment ---
echo "=== Test 2: Dynamic PVC Persistence ==="
echo ""

POD=$(kubectl get pod -l app=persistent-app -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

echo "[1/4] Writing test data to ${POD}..."
kubectl exec ${POD} -n ${NAMESPACE} -- sh -c 'echo "DYNAMIC_TEST: written at $(date)" > /app/data/dynamic-test.txt'
kubectl exec ${POD} -n ${NAMESPACE} -- cat /app/data/dynamic-test.txt
echo ""

echo "[2/4] Deleting the pod (Deployment will recreate it)..."
kubectl delete pod ${POD} -n ${NAMESPACE} --wait=true
echo ""

echo "[3/4] Waiting for new pod..."
kubectl wait --for=condition=Ready pod -l app=persistent-app -n ${NAMESPACE} --timeout=60s
NEW_POD=$(kubectl get pod -l app=persistent-app -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}')
echo "New pod: ${NEW_POD}"
echo ""

echo "[4/4] Verifying data survived pod deletion..."
echo "--- Data from before deletion: ---"
kubectl exec ${NEW_POD} -n ${NAMESPACE} -- cat /app/data/dynamic-test.txt
echo ""

echo "============================================"
echo "  All persistence tests passed!"
echo "============================================"
echo ""
echo "Summary:"
echo "  - Static PVC: Data survived pod deletion"
echo "  - Dynamic PVC: Data survived pod deletion"
echo "  - Volume lifecycle is independent of pod lifecycle"
echo ""
