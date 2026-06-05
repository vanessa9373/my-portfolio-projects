#!/bin/bash
set -e

echo "========================================="
echo "K8S-09: Labeling Nodes for Scheduling Demos"
echo "========================================="

echo ""
echo "Fetching cluster nodes..."
NODES=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name" 2>/dev/null)

if [ -z "${NODES}" ]; then
  echo "ERROR: No nodes found. Ensure kubectl is connected to a cluster."
  exit 1
fi

NODE_ARRAY=(${NODES})
NODE_COUNT=${#NODE_ARRAY[@]}

echo "Found ${NODE_COUNT} nodes: ${NODES}"
echo ""

# Label nodes with disk type
echo "[1/4] Labeling nodes with disk type..."
for i in "${!NODE_ARRAY[@]}"; do
  NODE="${NODE_ARRAY[$i]}"
  if (( i % 2 == 0 )); then
    kubectl label node "${NODE}" disk=ssd --overwrite 2>/dev/null || true
    echo "  ${NODE}: disk=ssd"
  else
    kubectl label node "${NODE}" disk=hdd --overwrite 2>/dev/null || true
    echo "  ${NODE}: disk=hdd"
  fi
done

# Label nodes with environment
echo ""
echo "[2/4] Labeling nodes with environment..."
for NODE in "${NODE_ARRAY[@]}"; do
  kubectl label node "${NODE}" environment=production --overwrite 2>/dev/null || true
  echo "  ${NODE}: environment=production"
done

# Label last node as GPU node (if more than 2 nodes)
echo ""
echo "[3/4] Labeling GPU nodes..."
if [ ${NODE_COUNT} -ge 3 ]; then
  GPU_NODE="${NODE_ARRAY[$((NODE_COUNT-1))]}"
  kubectl label node "${GPU_NODE}" gpu=nvidia --overwrite 2>/dev/null || true
  echo "  ${GPU_NODE}: gpu=nvidia"
  echo ""
  echo "  To taint this GPU node (prevents general workloads):"
  echo "  kubectl taint nodes ${GPU_NODE} gpu=nvidia:NoSchedule"
else
  echo "  [SKIP] Need at least 3 nodes for GPU demo"
fi

# Verify zone labels exist (usually auto-applied by cloud provider)
echo ""
echo "[4/4] Verifying topology zone labels..."
for NODE in "${NODE_ARRAY[@]}"; do
  ZONE=$(kubectl get node "${NODE}" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "not-set")
  echo "  ${NODE}: zone=${ZONE}"
  if [ "${ZONE}" = "not-set" ] || [ -z "${ZONE}" ]; then
    # Assign a zone if not set (for local clusters like kind/minikube)
    ZONE_INDEX=$((RANDOM % 3))
    ZONES=("us-east-1a" "us-east-1b" "us-east-1c")
    kubectl label node "${NODE}" topology.kubernetes.io/zone="${ZONES[$ZONE_INDEX]}" --overwrite 2>/dev/null || true
    echo "    -> Assigned: ${ZONES[$ZONE_INDEX]}"
  fi
done

echo ""
echo "========================================="
echo "Node labeling complete!"
echo "========================================="
echo ""
echo "Node labels summary:"
kubectl get nodes --show-labels | head -20
