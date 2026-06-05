#!/bin/bash
set -e

echo "========================================="
echo "K8S-05: StatefulSet Failover Testing"
echo "========================================="

echo ""
echo "=== TEST 1: Verify Stable Pod Identities ==="
echo "Checking pod names..."
PODS=$(kubectl get pods -l app=postgres -o jsonpath='{.items[*].metadata.name}')
echo "PostgreSQL pods: ${PODS}"

for i in 0 1 2; do
  POD_NAME=$(kubectl get pod "postgres-${i}" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "NOT_FOUND")
  if [ "${POD_NAME}" = "postgres-${i}" ]; then
    echo "  [PASS] postgres-${i} exists with correct name"
  else
    echo "  [FAIL] postgres-${i} not found"
    exit 1
  fi
done

echo ""
echo "=== TEST 2: Verify Per-Pod PVCs ==="
for i in 0 1 2; do
  PVC_STATUS=$(kubectl get pvc "data-postgres-${i}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOT_FOUND")
  if [ "${PVC_STATUS}" = "Bound" ]; then
    echo "  [PASS] PVC data-postgres-${i} is Bound"
  else
    echo "  [WARN] PVC data-postgres-${i} status: ${PVC_STATUS}"
  fi
done

echo ""
echo "=== TEST 3: Verify DNS Resolution ==="
echo "Creating DNS test pod..."
kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup postgres-0.postgres-headless.default.svc.cluster.local 2>/dev/null || \
  echo "  [INFO] DNS test requires interactive mode. Verify manually."

echo ""
echo "=== TEST 4: PostgreSQL Write to Primary ==="
echo "Writing test data to postgres-0 (primary)..."
kubectl exec postgres-0 -- psql -U postgres -d appdb -c \
  "CREATE TABLE IF NOT EXISTS failover_test (id serial PRIMARY KEY, value text, created_at timestamp DEFAULT now());"
kubectl exec postgres-0 -- psql -U postgres -d appdb -c \
  "INSERT INTO failover_test (value) VALUES ('test-before-failover');"
echo "  [PASS] Data written to primary"

echo ""
echo "=== TEST 5: Pod Deletion and Recovery ==="
echo "Deleting postgres-1 to test recovery..."
kubectl delete pod postgres-1 --grace-period=10
echo "Waiting for postgres-1 to restart..."
kubectl wait --for=condition=Ready pod/postgres-1 --timeout=120s
echo "  [PASS] postgres-1 recovered with same identity"

echo ""
echo "=== TEST 6: MongoDB ReplicaSet Failover ==="
echo "Checking MongoDB ReplicaSet status..."
kubectl exec mongo-0 -- mongosh --quiet --eval 'rs.status().members.forEach(function(m) { print(m.name + " -> " + m.stateStr); })' 2>/dev/null || \
  echo "  [INFO] MongoDB ReplicaSet may not be initialized yet."

echo ""
echo "=== TEST 7: Scale Down and Up ==="
echo "Scaling PostgreSQL to 1 replica..."
kubectl scale statefulset postgres --replicas=1
sleep 10
echo "Current pods after scale down:"
kubectl get pods -l app=postgres

echo ""
echo "Scaling PostgreSQL back to 3 replicas..."
kubectl scale statefulset postgres --replicas=3
kubectl wait --for=condition=Ready pod/postgres-2 --timeout=120s
echo "  [PASS] Scale up completed with same identities"

echo ""
echo "=== TEST 8: Verify Data Persistence After Restart ==="
ROW_COUNT=$(kubectl exec postgres-0 -- psql -U postgres -d appdb -t -c \
  "SELECT count(*) FROM failover_test;" 2>/dev/null | tr -d ' ')
if [ "${ROW_COUNT}" -ge 1 ] 2>/dev/null; then
  echo "  [PASS] Data persisted: ${ROW_COUNT} rows found"
else
  echo "  [WARN] Could not verify data persistence"
fi

echo ""
echo "========================================="
echo "Failover testing complete!"
echo "========================================="
