#!/bin/bash
set -e

TARGET_VERSION="${1:-1.29.0}"
PACKAGE_VERSION="${TARGET_VERSION}-1.1"

echo "============================================="
echo " Kubernetes Cluster Upgrade Script"
echo " Target version: v${TARGET_VERSION}"
echo "============================================="

# Check current version
echo ""
echo "[1/8] Current cluster version:"
kubectl version --short 2>/dev/null || kubectl version
echo ""
kubectl get nodes -o wide --no-headers | sed 's/^/    /'

# Verify upgrade path (must be one minor version at a time)
CURRENT_MINOR=$(kubectl version -o json 2>/dev/null | \
  python3 -c "import sys,json; v=json.load(sys.stdin)['serverVersion']; print(v['minor'].rstrip('+'))")
TARGET_MINOR=$(echo "${TARGET_VERSION}" | cut -d. -f2)
VERSION_DIFF=$((TARGET_MINOR - CURRENT_MINOR))

if [[ ${VERSION_DIFF} -gt 1 ]]; then
  echo "ERROR: Cannot skip minor versions. Current minor: ${CURRENT_MINOR}, target: ${TARGET_MINOR}"
  echo "Upgrade one minor version at a time."
  exit 1
fi

if [[ ${VERSION_DIFF} -lt 0 ]]; then
  echo "ERROR: Target version is older than current version. Downgrades are not supported."
  exit 1
fi

# Pre-flight checks
echo ""
echo "[2/8] Running pre-flight checks..."
echo "  Checking node health..."
UNHEALTHY_NODES=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
if [[ ${UNHEALTHY_NODES} -gt 0 ]]; then
  echo "WARNING: ${UNHEALTHY_NODES} node(s) are not Ready. Fix before upgrading."
  kubectl get nodes | grep -v "Ready"
fi

echo "  Checking for PodDisruptionBudgets..."
kubectl get pdb -A --no-headers 2>/dev/null | sed 's/^/    /'

# Take etcd backup before upgrade
echo ""
echo "[3/8] Taking etcd backup before upgrade..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/etcd-backup.sh" ]]; then
  "${SCRIPT_DIR}/etcd-backup.sh"
else
  echo "  WARNING: etcd-backup.sh not found. Take a manual backup before proceeding."
fi

# Check upgrade plan
echo ""
echo "[4/8] Checking kubeadm upgrade plan..."
sudo kubeadm upgrade plan

# Confirm upgrade
echo ""
read -p "Proceed with upgrade to v${TARGET_VERSION}? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Upgrade cancelled."
  exit 0
fi

# Upgrade kubeadm
echo ""
echo "[5/8] Upgrading kubeadm..."
sudo apt-get update -q
sudo apt-get install -y --allow-change-held-packages "kubeadm=${PACKAGE_VERSION}"
kubeadm version

# Apply control plane upgrade
echo ""
echo "[6/8] Upgrading control plane..."
sudo kubeadm upgrade apply "v${TARGET_VERSION}" --yes

echo "  Control plane upgraded successfully."

# Upgrade kubelet and kubectl on control plane
echo ""
echo "[7/8] Upgrading kubelet and kubectl on control plane node..."
sudo apt-get install -y --allow-change-held-packages \
  "kubelet=${PACKAGE_VERSION}" \
  "kubectl=${PACKAGE_VERSION}"
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "  Waiting for control plane node to be Ready..."
sleep 15
kubectl get nodes

# Upgrade worker nodes
echo ""
echo "[8/8] Worker node upgrade instructions:"
echo ""
WORKERS=$(kubectl get nodes --no-headers -l '!node-role.kubernetes.io/control-plane' | awk '{print $1}')
for WORKER in ${WORKERS}; do
  echo "  For ${WORKER}:"
  echo "    1. kubectl drain ${WORKER} --ignore-daemonsets --delete-emptydir-data"
  echo "    2. SSH to ${WORKER} and run:"
  echo "       sudo apt-get update"
  echo "       sudo apt-get install -y kubeadm=${PACKAGE_VERSION} kubelet=${PACKAGE_VERSION}"
  echo "       sudo kubeadm upgrade node"
  echo "       sudo systemctl daemon-reload"
  echo "       sudo systemctl restart kubelet"
  echo "    3. kubectl uncordon ${WORKER}"
  echo ""
done

echo "============================================="
echo " Control plane upgrade to v${TARGET_VERSION} complete!"
echo " Upgrade worker nodes using instructions above."
echo "============================================="
