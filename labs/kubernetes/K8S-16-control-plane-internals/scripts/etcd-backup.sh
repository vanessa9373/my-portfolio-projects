#!/bin/bash
set -e

BACKUP_DIR="${BACKUP_DIR:-/var/lib/etcd-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# etcd connection parameters
ETCD_ENDPOINTS="${ETCD_ENDPOINTS:-https://127.0.0.1:2379}"
ETCD_CACERT="${ETCD_CACERT:-/etc/kubernetes/pki/etcd/ca.crt}"
ETCD_CERT="${ETCD_CERT:-/etc/kubernetes/pki/etcd/server.crt}"
ETCD_KEY="${ETCD_KEY:-/etc/kubernetes/pki/etcd/server.key}"

echo "============================================="
echo " etcd Backup Script"
echo " Timestamp: ${TIMESTAMP}"
echo "============================================="

# Create backup directory if it does not exist
mkdir -p "${BACKUP_DIR}"

# Verify etcd is healthy
echo ""
echo "[1/4] Checking etcd health..."
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints="${ETCD_ENDPOINTS}" \
  --cacert="${ETCD_CACERT}" \
  --cert="${ETCD_CERT}" \
  --key="${ETCD_KEY}"

# Take snapshot
echo ""
echo "[2/4] Taking etcd snapshot..."
ETCDCTL_API=3 etcdctl snapshot save "${SNAPSHOT_FILE}" \
  --endpoints="${ETCD_ENDPOINTS}" \
  --cacert="${ETCD_CACERT}" \
  --cert="${ETCD_CERT}" \
  --key="${ETCD_KEY}"

echo "  Snapshot saved to: ${SNAPSHOT_FILE}"

# Verify snapshot integrity
echo ""
echo "[3/4] Verifying snapshot integrity..."
ETCDCTL_API=3 etcdctl snapshot status "${SNAPSHOT_FILE}" --write-out=table

SNAPSHOT_SIZE=$(ls -lh "${SNAPSHOT_FILE}" | awk '{print $5}')
echo "  Snapshot size: ${SNAPSHOT_SIZE}"

# Clean up old backups
echo ""
echo "[4/4] Cleaning up backups older than ${RETENTION_DAYS} days..."
DELETED_COUNT=$(find "${BACKUP_DIR}" -name "etcd-snapshot-*.db" -mtime +"${RETENTION_DAYS}" -print -delete | wc -l)
echo "  Deleted ${DELETED_COUNT} old backup(s)."

# List remaining backups
echo ""
echo "Current backups:"
ls -lht "${BACKUP_DIR}"/etcd-snapshot-*.db 2>/dev/null | head -10 || echo "  No backups found"

TOTAL_COUNT=$(ls "${BACKUP_DIR}"/etcd-snapshot-*.db 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" 2>/dev/null | awk '{print $1}')
echo ""
echo "Total backups: ${TOTAL_COUNT}"
echo "Total size: ${TOTAL_SIZE}"

echo ""
echo "============================================="
echo " etcd Backup Complete"
echo "============================================="
