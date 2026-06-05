#!/bin/bash
set -e

echo "========================================="
echo "K8S-07: Cleaning Up DaemonSets & Resource Governance"
echo "========================================="

echo ""
echo "[1/4] Deleting namespace team-a (includes all namespaced resources)..."
kubectl delete namespace team-a --ignore-not-found=true

echo ""
echo "[2/4] Deleting DaemonSet and associated RBAC..."
kubectl delete daemonset fluentd-logging --ignore-not-found=true
kubectl delete serviceaccount fluentd --ignore-not-found=true
kubectl delete clusterrolebinding fluentd --ignore-not-found=true
kubectl delete clusterrole fluentd --ignore-not-found=true

echo ""
echo "[3/4] Deleting PriorityClasses..."
kubectl delete priorityclass critical-system --ignore-not-found=true
kubectl delete priorityclass standard-workload --ignore-not-found=true
kubectl delete priorityclass background-batch --ignore-not-found=true

echo ""
echo "[4/4] Verifying cleanup..."
echo "DaemonSets:"
kubectl get daemonset fluentd-logging 2>/dev/null || echo "  None"
echo "PriorityClasses (custom):"
kubectl get priorityclass | grep -E "critical-system|standard-workload|background-batch" || echo "  None"

echo ""
echo "========================================="
echo "Cleanup complete!"
echo "========================================="
