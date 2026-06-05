#!/bin/bash
set -e

SNAPSHOT_FILE="${1}"
RESTORE_DIR="${RESTORE_DIR:-/var/lib/etcd-restored}"
MANIFESTS_DIR="/etc/kubernetes/manifests"
MANIFESTS_BACKUP="/tmp/k8s-manifests-backup"

# etcd configuration
ETCD_NAME="${ETCD_NAME:-control-plane}"
ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER:-control-plane=https://127.0.0.1:2380}"
ETCD_INITIAL_ADVERTISE_PEER_URLS="${ETCD_INITIAL_ADVERTISE_PEER_URLS:-https://127.0.0.1:2380}"

echo "============================================="
echo " etcd Restore Script"
echo " WARNING: This will restore etcd from backup"
echo "============================================="

# Validate arguments
if [[ -z "${SNAPSHOT_FILE}" ]]; then
  echo "Usage: $0 <snapshot-file>"
  echo ""
  echo "Example:"
  echo "  $0 /var/lib/etcd-backups/etcd-snapshot-20250115-060000.db"
  echo ""
  echo "Available snapshots:"
  ls -lht /var/lib/etcd-backups/etcd-snapshot-*.db 2>/dev/null || echo "  None found"
  exit 1
fi

if [[ ! -f "${SNAPSHOT_FILE}" ]]; then
  echo "ERROR: Snapshot file not found: ${SNAPSHOT_FILE}"
  exit 1
fi

# Verify snapshot integrity
echo ""
echo "[1/6] Verifying snapshot integrity..."
ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" --write-out=table

# Confirm restore
echo ""
echo "WARNING: This will:"
echo "  1. Stop kube-apiserver and etcd"
echo "  2. Restore etcd data from: ${SNAPSHOT_FILE}"
echo "  3. Restart control plane components"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Restore cancelled."
  exit 0
fi

# Backup current manifests
echo ""
echo "[2/6] Backing up current static pod manifests..."
mkdir -p "${MANIFESTS_BACKUP}"
cp "${MANIFESTS_DIR}/kube-apiserver.yaml" "${MANIFESTS_BACKUP}/" 2>/dev/null || true
cp "${MANIFESTS_DIR}/etcd.yaml" "${MANIFESTS_BACKUP}/" 2>/dev/null || true
echo "  Manifests backed up to: ${MANIFESTS_BACKUP}"

# Stop control plane
echo ""
echo "[3/6] Stopping control plane components..."
mv "${MANIFESTS_DIR}/kube-apiserver.yaml" /tmp/kube-apiserver.yaml
mv "${MANIFESTS_DIR}/etcd.yaml" /tmp/etcd.yaml

echo "  Waiting for components to stop..."
sleep 15

# Verify components are stopped
if crictl ps 2>/dev/null | grep -q etcd; then
  echo "  WARNING: etcd container still running. Waiting additional 15 seconds..."
  sleep 15
fi

# Restore from snapshot
echo ""
echo "[4/6] Restoring etcd from snapshot..."
rm -rf "${RESTORE_DIR}"

ETCDCTL_API=3 etcdctl snapshot restore "${SNAPSHOT_FILE}" \
  --data-dir="${RESTORE_DIR}" \
  --name="${ETCD_NAME}" \
  --initial-cluster="${ETCD_INITIAL_CLUSTER}" \
  --initial-advertise-peer-urls="${ETCD_INITIAL_ADVERTISE_PEER_URLS}"

echo "  Data restored to: ${RESTORE_DIR}"

# Update etcd manifest to use restored directory
echo ""
echo "[5/6] Updating etcd data directory in manifest..."
sed "s|/var/lib/etcd|${RESTORE_DIR}|g" /tmp/etcd.yaml > "${MANIFESTS_DIR}/etcd.yaml"

# Restart control plane
echo ""
echo "[6/6] Restarting control plane..."
mv /tmp/kube-apiserver.yaml "${MANIFESTS_DIR}/kube-apiserver.yaml"

echo "  Waiting for control plane to recover..."
sleep 30

# Verify cluster health
echo ""
echo "Verifying cluster health..."
RETRY=0
MAX_RETRIES=12
while [[ $RETRY -lt $MAX_RETRIES ]]; do
  if kubectl get nodes &>/dev/null; then
    echo "  Cluster is healthy!"
    kubectl get nodes
    echo ""
    kubectl get pods -n kube-system --no-headers | head -10
    break
  fi
  RETRY=$((RETRY + 1))
  echo "  Waiting for API server... (attempt ${RETRY}/${MAX_RETRIES})"
  sleep 10
done

if [[ $RETRY -eq $MAX_RETRIES ]]; then
  echo "ERROR: Cluster did not recover within expected time."
  echo "Check control plane logs for errors."
  exit 1
fi

echo ""
echo "============================================="
echo " etcd Restore Complete"
echo " Restored from: ${SNAPSHOT_FILE}"
echo "============================================="
