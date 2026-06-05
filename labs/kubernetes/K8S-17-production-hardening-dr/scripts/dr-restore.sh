#!/bin/bash
set -e

BACKUP_NAME="${1}"
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"

echo "============================================="
echo " Disaster Recovery Restore"
echo "============================================="

# Validate arguments
if [[ -z "${BACKUP_NAME}" ]]; then
  echo "Usage: $0 <backup-name> [--include-namespaces=<ns>]"
  echo ""
  echo "Available backups:"
  velero get backups 2>/dev/null || echo "  Cannot connect to Velero"
  exit 1
fi

# Verify backup exists and is valid
echo ""
echo "[1/5] Verifying backup: ${BACKUP_NAME}..."
BACKUP_PHASE=$(velero backup get "${BACKUP_NAME}" -o json 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('phase','NotFound'))" 2>/dev/null || echo "NotFound")

if [[ "${BACKUP_PHASE}" != "Completed" ]]; then
  echo "ERROR: Backup '${BACKUP_NAME}' status is '${BACKUP_PHASE}'"
  echo "Only Completed backups can be restored."
  exit 1
fi
echo "  Backup is valid (status: Completed)"

# Display backup contents
echo ""
echo "[2/5] Backup contents:"
velero backup describe "${BACKUP_NAME}" --details 2>/dev/null | \
  grep -A 20 "Resource List:" | head -25

# Confirm restore
echo ""
echo "WARNING: This will restore resources from backup '${BACKUP_NAME}'"
echo "  Restore name: ${RESTORE_NAME}"
echo ""
read -p "Proceed with restore? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Restore cancelled."
  exit 0
fi

# Execute restore
echo ""
echo "[3/5] Executing restore..."
INCLUDE_NS="${2}"
if [[ -n "${INCLUDE_NS}" ]]; then
  velero restore create "${RESTORE_NAME}" \
    --from-backup "${BACKUP_NAME}" \
    "${INCLUDE_NS}" \
    --restore-volumes=true \
    --wait
else
  velero restore create "${RESTORE_NAME}" \
    --from-backup "${BACKUP_NAME}" \
    --restore-volumes=true \
    --wait
fi

# Check restore status
echo ""
echo "[4/5] Restore status:"
velero restore describe "${RESTORE_NAME}" --details

RESTORE_PHASE=$(velero restore get "${RESTORE_NAME}" -o json 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('status',{}).get('phase','Unknown'))" 2>/dev/null || echo "Unknown")

if [[ "${RESTORE_PHASE}" == "Completed" ]]; then
  echo "  Restore completed successfully!"
elif [[ "${RESTORE_PHASE}" == "PartiallyFailed" ]]; then
  echo "  WARNING: Restore partially failed. Check logs:"
  velero restore logs "${RESTORE_NAME}" | grep -E "error|warning" | tail -20
else
  echo "  Restore status: ${RESTORE_PHASE}"
fi

# Verify restored resources
echo ""
echo "[5/5] Verifying restored resources..."
echo ""
echo "  Pods:"
kubectl get pods -A --no-headers 2>/dev/null | grep -v "kube-system" | head -20 | sed 's/^/    /'
echo ""
echo "  Services:"
kubectl get svc -A --no-headers 2>/dev/null | grep -v "kube-system" | head -10 | sed 's/^/    /'
echo ""
echo "  PVCs:"
kubectl get pvc -A --no-headers 2>/dev/null | head -10 | sed 's/^/    /'

echo ""
echo "============================================="
echo " Restore complete: ${RESTORE_NAME}"
echo " From backup: ${BACKUP_NAME}"
echo "============================================="
