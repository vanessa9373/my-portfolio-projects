#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================="
echo " K8S-17: Production Hardening & DR Deployment"
echo "============================================="

# Check prerequisites
echo ""
echo "[1/7] Checking prerequisites..."
for cmd in kubectl velero cosign; do
  if command -v "$cmd" &> /dev/null; then
    echo "  $cmd: found"
  else
    echo "  $cmd: NOT FOUND (install before proceeding)"
  fi
done

# Apply Pod Security Admission
echo ""
echo "[2/7] Configuring Pod Security Admission..."
kubectl apply -f "$PROJECT_DIR/manifests/pod-security-admission.yaml"
echo "  Namespaces configured with PSA labels:"
kubectl get namespaces -L pod-security.kubernetes.io/enforce --no-headers 2>/dev/null | \
  awk '{if ($NF != "<none>") print "    " $1 ": " $NF}'

# Install Velero (if not already installed)
echo ""
echo "[3/7] Checking Velero installation..."
if kubectl get namespace velero &>/dev/null; then
  echo "  Velero namespace exists. Checking pods..."
  kubectl get pods -n velero --no-headers | sed 's/^/    /'
else
  echo "  Velero not installed. Install with:"
  echo "    velero install \\"
  echo "      --provider aws \\"
  echo "      --plugins velero/velero-plugin-for-aws:v1.9.0 \\"
  echo "      --bucket k8s-prod-velero-backups \\"
  echo "      --backup-location-config region=us-east-1 \\"
  echo "      --snapshot-location-config region=us-east-1 \\"
  echo "      --secret-file ./credentials-velero \\"
  echo "      --use-volume-snapshots=true \\"
  echo "      --wait"
fi

# Apply backup schedules
echo ""
echo "[4/7] Applying Velero backup schedules..."
kubectl apply -f "$PROJECT_DIR/manifests/velero-schedule.yaml" 2>/dev/null || \
  echo "  WARNING: Velero CRDs not found. Install Velero first."
kubectl apply -f "$PROJECT_DIR/manifests/velero-backup.yaml" 2>/dev/null || true

# Configure etcd encryption
echo ""
echo "[5/7] etcd Encryption at Rest..."
echo "  Manual step required on control plane node:"
echo "    sudo cp manifests/etcd-encryption-config.yaml /etc/kubernetes/encryption-config.yaml"
echo "    sudo chmod 600 /etc/kubernetes/encryption-config.yaml"
echo "  Then add to kube-apiserver:"
echo "    --encryption-provider-config=/etc/kubernetes/encryption-config.yaml"

# Install Kyverno and apply cosign policy
echo ""
echo "[6/7] Applying image signing policy..."
if kubectl get crd clusterpolicies.kyverno.io &>/dev/null; then
  kubectl apply -f "$PROJECT_DIR/manifests/cosign-policy.yaml"
  echo "  Cosign verification policy applied."
else
  echo "  Kyverno CRDs not found. Install Kyverno first:"
  echo "    helm repo add kyverno https://kyverno.github.io/kyverno/"
  echo "    helm install kyverno kyverno/kyverno -n kyverno --create-namespace"
fi

# Verification
echo ""
echo "[7/7] Deployment verification..."
echo ""
echo "  Pod Security Standards:"
kubectl get namespaces -L pod-security.kubernetes.io/enforce --no-headers 2>/dev/null | \
  awk '{if ($NF != "<none>") print "    " $1 ": " $NF}'
echo ""
echo "  Velero Schedules:"
velero get schedules 2>/dev/null | sed 's/^/    /' || echo "    Velero not available"
echo ""
echo "  Backup Locations:"
velero get backup-locations 2>/dev/null | sed 's/^/    /' || echo "    Velero not available"

echo ""
echo "============================================="
echo " Deployment complete!"
echo ""
echo " Next steps:"
echo "   1. Configure etcd encryption on control plane"
echo "   2. Run dr-backup.sh for initial backup"
echo "   3. Test DR with dr-restore.sh"
echo "   4. Set up cosign key pair for CI pipeline"
echo "============================================="
