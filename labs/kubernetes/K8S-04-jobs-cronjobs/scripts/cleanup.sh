#!/bin/bash
set -e

echo "============================================"
echo "  K8S-04: Jobs, CronJobs & Init Containers"
echo "  — Cleanup"
echo "============================================"

echo ""
echo "This will delete the entire k8s-batch namespace"
echo "and ALL resources within it (jobs, cronjobs, pods)."
echo ""

read -p "Are you sure? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Deleting namespace k8s-batch..."
kubectl delete namespace k8s-batch --timeout=60s

echo ""
echo "============================================"
echo "  Cleanup Complete!"
echo "============================================"
echo ""
echo "Verify:"
echo "  kubectl get namespaces"
echo "  kubectl get jobs -A"
echo "  kubectl get cronjobs -A"
echo ""
