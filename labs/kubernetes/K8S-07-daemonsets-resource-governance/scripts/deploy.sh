#!/bin/bash
set -e

echo "========================================="
echo "K8S-07: Deploying DaemonSets & Resource Governance"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/7] Deploying PriorityClasses (cluster-scoped)..."
kubectl apply -f "${MANIFESTS_DIR}/priority-classes.yaml"

echo ""
echo "[2/7] Deploying Fluentd DaemonSet..."
kubectl apply -f "${MANIFESTS_DIR}/daemonset-logging.yaml"

echo ""
echo "[3/7] Creating namespace team-a..."
kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[4/7] Applying ResourceQuota to team-a..."
kubectl apply -f "${MANIFESTS_DIR}/resourcequota.yaml" -n team-a

echo ""
echo "[5/7] Applying LimitRange to team-a..."
kubectl apply -f "${MANIFESTS_DIR}/limitrange.yaml" -n team-a

echo ""
echo "[6/7] Deploying QoS demo pods..."
kubectl apply -f "${MANIFESTS_DIR}/qos-guaranteed.yaml" -n team-a
kubectl apply -f "${MANIFESTS_DIR}/qos-burstable.yaml" -n team-a
# Note: BestEffort pod will get LimitRange defaults injected
# making it Burstable. Deploy without LimitRange for true BestEffort demo.
kubectl apply -f "${MANIFESTS_DIR}/qos-besteffort.yaml" -n team-a || \
  echo "  [INFO] BestEffort pod may be rejected by ResourceQuota (expected if LimitRange not yet active)"

echo ""
echo "[7/7] Deploying app with PDB..."
kubectl apply -f "${MANIFESTS_DIR}/pdb.yaml" -n team-a

echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo ""
echo "DaemonSet status:"
kubectl get daemonset fluentd-logging
echo ""
echo "ResourceQuota usage:"
kubectl describe resourcequota team-a-quota -n team-a 2>/dev/null | grep -A20 "Resource"
echo ""
echo "PDB status:"
kubectl get pdb -n team-a
echo ""
echo "QoS classes:"
for pod in qos-guaranteed qos-burstable qos-besteffort; do
  QOS=$(kubectl get pod ${pod} -n team-a -o jsonpath='{.status.qosClass}' 2>/dev/null || echo "N/A")
  echo "  ${pod}: ${QOS}"
done
