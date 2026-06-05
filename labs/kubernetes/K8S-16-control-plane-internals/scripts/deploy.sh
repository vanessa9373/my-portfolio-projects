#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-16: Control Plane Internals Deployment"
echo " etcd, API Server & Scheduler Configuration"
echo "============================================="

# Check prerequisites
echo ""
echo "[1/7] Checking prerequisites..."
for cmd in kubectl etcdctl; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "WARNING: $cmd not found. Some steps may require manual execution."
  fi
done

# Verify control plane access
if ! kubectl get nodes &> /dev/null; then
  echo "ERROR: Cannot connect to Kubernetes cluster."
  exit 1
fi

echo "  Cluster connection verified."
kubectl get nodes --no-headers | sed 's/^/    /'

# Check control plane components
echo ""
echo "[2/7] Verifying control plane components..."
kubectl get pods -n kube-system -l tier=control-plane --no-headers 2>/dev/null | sed 's/^/    /' || \
  echo "    No control-plane labeled pods found (may be running as systemd services)"

# Deploy etcd backup CronJob
echo ""
echo "[3/7] Deploying etcd backup CronJob..."
kubectl apply -f "$PROJECT_DIR/manifests/etcd-backup-cronjob.yaml"
echo "  CronJob schedule: every 6 hours"

# Apply audit policy
echo ""
echo "[4/7] Applying audit policy..."
echo "  NOTE: Audit policy must be placed on control plane node:"
echo "    sudo cp manifests/audit-policy.yaml /etc/kubernetes/audit-policy.yaml"
echo "  Then add these flags to kube-apiserver:"
echo "    --audit-policy-file=/etc/kubernetes/audit-policy.yaml"
echo "    --audit-log-path=/var/log/kubernetes/audit.log"
echo "    --audit-log-maxage=30"
echo "    --audit-log-maxbackup=10"
echo "    --audit-log-maxsize=100"

# Apply API Priority and Fairness
echo ""
echo "[5/7] Configuring API Priority and Fairness..."
kubectl apply -f "$PROJECT_DIR/manifests/api-priority-fairness.yaml"
echo "  FlowSchemas and PriorityLevelConfigurations applied."

# Apply scheduler configuration
echo ""
echo "[6/7] Applying scheduler configuration..."
echo "  NOTE: Scheduler config must be placed on control plane node:"
echo "    sudo cp manifests/scheduler-config.yaml /etc/kubernetes/scheduler-config.yaml"
echo "  Then add this flag to kube-scheduler:"
echo "    --config=/etc/kubernetes/scheduler-config.yaml"

# Verify deployment
echo ""
echo "[7/7] Verifying deployment..."
echo ""
echo "  etcd Backup CronJobs:"
kubectl get cronjobs -n kube-system --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  FlowSchemas:"
kubectl get flowschemas --no-headers 2>/dev/null | head -10 | sed 's/^/    /'
echo ""
echo "  PriorityLevelConfigurations:"
kubectl get prioritylevelconfigurations --no-headers 2>/dev/null | head -10 | sed 's/^/    /'

echo ""
echo "============================================="
echo " Deployment complete!"
echo ""
echo " Manual steps required:"
echo "   1. Copy audit-policy.yaml to control plane"
echo "   2. Copy scheduler-config.yaml to control plane"
echo "   3. Update kube-apiserver and kube-scheduler manifests"
echo "   4. Run etcd-backup.sh for initial backup"
echo "============================================="
