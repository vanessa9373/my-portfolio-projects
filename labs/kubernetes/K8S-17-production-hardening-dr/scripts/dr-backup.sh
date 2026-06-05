#!/bin/bash
set -e

BACKUP_NAME="${1:-manual-backup-$(date +%Y%m%d-%H%M%S)}"
NAMESPACES="${NAMESPACES:-production,staging,monitoring}"

echo "============================================="
echo " Disaster Recovery Backup"
echo " Backup Name: ${BACKUP_NAME}"
echo " Namespaces: ${NAMESPACES}"
echo "============================================="

# Check Velero is running
echo ""
echo "[1/4] Verifying Velero status..."
if ! velero get backup-locations &>/dev/null; then
  echo "ERROR: Velero is not running or not configured."
  exit 1
fi
velero get backup-locations

# Create the backup
echo ""
echo "[2/4] Creating backup..."
velero backup create "${BACKUP_NAME}" \
  --include-namespaces="${NAMESPACES}" \
  --snapshot-volumes=true \
  --default-volumes-to-fs-backup=true \
  --ttl=720h \
  --wait

# Verify backup status
echo ""
echo "[3/4] Verifying backup..."
BACKUP_STATUS=$(velero backup get "${BACKUP_NAME}" -o json 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('phase','Unknown'))" 2>/dev/null || echo "Unknown")

if [[ "${BACKUP_STATUS}" == "Completed" ]]; then
  echo "  Backup completed successfully."
else
  echo "  WARNING: Backup status is '${BACKUP_STATUS}'"
  velero backup describe "${BACKUP_NAME}" --details
  velero backup logs "${BACKUP_NAME}" | tail -20
fi

# Display backup details
echo ""
echo "[4/4] Backup details:"
velero backup describe "${BACKUP_NAME}" --details 2>/dev/null || true

echo ""
echo "Recent backups:"
velero get backups | head -10

echo ""
echo "============================================="
echo " Backup complete: ${BACKUP_NAME}"
echo ""
echo " To restore from this backup:"
echo "   velero restore create --from-backup ${BACKUP_NAME}"
echo "============================================="
