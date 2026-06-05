#!/bin/bash
set -e

echo "Installing Crossplane..."

# Add Crossplane Helm repository
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Create namespace
kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

# Install Crossplane
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --set args='{"--enable-composition-revisions","--enable-environment-configs"}' \
  --set resourcesCrossplane.limits.cpu=500m \
  --set resourcesCrossplane.limits.memory=512Mi \
  --set resourcesCrossplane.requests.cpu=100m \
  --set resourcesCrossplane.requests.memory=256Mi \
  --set resourcesRBACManager.limits.cpu=250m \
  --set resourcesRBACManager.limits.memory=256Mi \
  --set resourcesRBACManager.requests.cpu=100m \
  --set resourcesRBACManager.requests.memory=128Mi \
  --wait --timeout 300s

echo "Waiting for Crossplane pods to be ready..."
kubectl wait --for=condition=ready pod \
  -l app=crossplane \
  -n crossplane-system \
  --timeout=120s

echo "Crossplane installed successfully."
kubectl get pods -n crossplane-system

# Check if AWS credentials secret exists
if ! kubectl get secret aws-creds -n crossplane-system &>/dev/null; then
  echo ""
  echo "WARNING: AWS credentials secret 'aws-creds' not found."
  echo "Create it with:"
  echo "  kubectl create secret generic aws-creds \\"
  echo "    -n crossplane-system \\"
  echo "    --from-file=creds=./aws-credentials.txt"
  echo ""
  echo "aws-credentials.txt format:"
  echo "  [default]"
  echo "  aws_access_key_id = YOUR_ACCESS_KEY"
  echo "  aws_secret_access_key = YOUR_SECRET_KEY"
fi
