#!/bin/bash
set -e

echo "============================================"
echo "  K8S-04: Jobs, CronJobs & Init Containers"
echo "  — Deploy All"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo ""
echo "[1/6] Creating namespace and simple Job..."
kubectl apply -f "${MANIFESTS_DIR}/job-simple.yaml"

echo ""
echo "[2/6] Creating parallel Job..."
kubectl apply -f "${MANIFESTS_DIR}/job-parallel.yaml"

echo ""
echo "[3/6] Creating CronJob (scheduled every 5 min)..."
kubectl apply -f "${MANIFESTS_DIR}/cronjob.yaml"

echo ""
echo "[4/6] Creating Pod with Init Containers..."
kubectl apply -f "${MANIFESTS_DIR}/pod-init-container.yaml"

echo ""
echo "[5/6] Creating Pod with Sidecar Container..."
kubectl apply -f "${MANIFESTS_DIR}/pod-sidecar.yaml"

echo ""
echo "[6/6] Creating Pod with Lifecycle Hooks..."
kubectl apply -f "${MANIFESTS_DIR}/pod-lifecycle.yaml"

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"

echo ""
echo "--- Jobs ---"
kubectl get jobs -n k8s-batch
echo ""
echo "--- CronJobs ---"
kubectl get cronjobs -n k8s-batch
echo ""
echo "--- Pods ---"
kubectl get pods -n k8s-batch

echo ""
echo "Monitoring commands:"
echo "  Watch jobs:     kubectl get jobs -n k8s-batch -w"
echo "  Watch pods:     kubectl get pods -n k8s-batch -w"
echo "  Job logs:       kubectl logs job/db-migration -n k8s-batch"
echo "  Parallel logs:  kubectl logs -l job-name=report-generator -n k8s-batch --prefix"
echo "  Init logs:      kubectl logs app-with-init -n k8s-batch -c wait-for-db"
echo "  Sidecar logs:   kubectl logs app-with-sidecar -n k8s-batch -c log-shipper"
echo "  Trigger cron:   kubectl create job --from=cronjob/data-cleanup manual-run -n k8s-batch"
echo ""
