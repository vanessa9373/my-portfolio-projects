#!/bin/bash
set -e

CLUSTER_NAME="${1:?Usage: register-cluster.sh <cluster-name> <region> <environment>}"
CLUSTER_REGION="${2:?Usage: register-cluster.sh <cluster-name> <region> <environment>}"
CLUSTER_ENV="${3:?Usage: register-cluster.sh <cluster-name> <region> <environment>}"

echo "=== Registering Cluster: ${CLUSTER_NAME} ==="
echo "Region:      ${CLUSTER_REGION}"
echo "Environment: ${CLUSTER_ENV}"

# Ensure fleet-default namespace exists on management cluster
kubectl create namespace fleet-default --dry-run=client -o yaml | kubectl apply -f -

# Create a Cluster registration token
echo "[1/3] Creating registration token..."
cat <<EOF | kubectl apply -f -
apiVersion: fleet.cattle.io/v1alpha1
kind: ClusterRegistrationToken
metadata:
  name: ${CLUSTER_NAME}-token
  namespace: fleet-default
spec:
  ttl: 24h
EOF

# Wait for the token secret to be created
echo "[2/3] Waiting for token generation..."
sleep 5
TOKEN_SECRET=$(kubectl get clusterregistrationtoken "${CLUSTER_NAME}-token" \
  -n fleet-default \
  -o jsonpath='{.status.secretName}' 2>/dev/null || echo "")

if [ -z "${TOKEN_SECRET}" ]; then
  echo "Warning: Token secret not ready yet. Check: kubectl get clusterregistrationtoken -n fleet-default"
fi

# Create the Cluster resource with labels
echo "[3/3] Creating Cluster resource..."
cat <<EOF | kubectl apply -f -
apiVersion: fleet.cattle.io/v1alpha1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: fleet-default
  labels:
    environment: ${CLUSTER_ENV}
    region: ${CLUSTER_REGION}
    name: ${CLUSTER_NAME}
spec:
  kubeConfigSecret: ${CLUSTER_NAME}-kubeconfig
EOF

# Create kubeconfig secret (user must provide the actual kubeconfig)
if [ -n "${KUBECONFIG}" ] && [ -f "${KUBECONFIG}" ]; then
  echo "Creating kubeconfig secret from ${KUBECONFIG}..."
  kubectl create secret generic "${CLUSTER_NAME}-kubeconfig" \
    --from-file=value="${KUBECONFIG}" \
    --namespace fleet-default \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo ""
  echo "NOTE: Provide the spoke cluster's kubeconfig:"
  echo "  kubectl create secret generic ${CLUSTER_NAME}-kubeconfig \\"
  echo "    --from-file=value=/path/to/${CLUSTER_NAME}-kubeconfig \\"
  echo "    --namespace fleet-default"
fi

echo ""
echo "=== Cluster ${CLUSTER_NAME} Registered ==="
echo ""
echo "Verify registration:"
echo "  kubectl get clusters.fleet.cattle.io -n fleet-default"
echo ""
echo "Check cluster groups:"
echo "  kubectl get clustergroups -n fleet-default"
