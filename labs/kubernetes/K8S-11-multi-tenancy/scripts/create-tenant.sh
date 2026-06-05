#!/bin/bash
set -e

TEAM_NAME="${1:?Usage: create-tenant.sh <team-name> <cost-center>}"
COST_CENTER="${2:?Usage: create-tenant.sh <team-name> <cost-center>}"
NAMESPACE="team-${TEAM_NAME}"

echo "=== Creating Tenant: ${TEAM_NAME} ==="

# Create namespace
echo "[1/4] Creating namespace ${NAMESPACE}..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    tenant: "true"
    team: ${TEAM_NAME}
    cost-center: ${COST_CENTER}
    environment: production
EOF

# Apply default-deny NetworkPolicy
echo "[2/4] Applying network isolation..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
  egress:
    - to:
        - podSelector: {}
EOF

# Apply ResourceQuota
echo "[3/4] Applying resource quota..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-quota
  namespace: ${NAMESPACE}
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "50"
    services: "20"
    persistentvolumeclaims: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-limit-range
  namespace: ${NAMESPACE}
spec:
  limits:
    - type: Container
      default:
        cpu: 250m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "4"
        memory: 8Gi
      min:
        cpu: 50m
        memory: 64Mi
EOF

# Create RBAC for the team
echo "[4/4] Creating RBAC bindings..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TEAM_NAME}-admin
  namespace: ${NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
  - kind: Group
    name: ${TEAM_NAME}-developers
    apiGroup: rbac.authorization.k8s.io
EOF

echo ""
echo "=== Tenant ${TEAM_NAME} Created ==="
echo "Namespace:     ${NAMESPACE}"
echo "Cost Center:   ${COST_CENTER}"
echo "CPU Quota:     8 cores (requests) / 16 cores (limits)"
echo "Memory Quota:  16Gi (requests) / 32Gi (limits)"
echo "Pod Limit:     50"
