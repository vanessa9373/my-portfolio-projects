# Phase 7: GitOps & Continuous Delivery

**Difficulty:** Intermediate | **Time:** 4-5 hours | **Prerequisites:** Phase 6

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Step-by-Step Implementation](#3-step-by-step-implementation)
4. [Configuration Walkthrough](#4-configuration-walkthrough)
5. [Verification Checklist](#5-verification-checklist)
6. [Troubleshooting](#6-troubleshooting)
7. [Key Decisions & Trade-offs](#7-key-decisions--trade-offs)
8. [Production Considerations](#8-production-considerations)
9. [Next Phase](#9-next-phase)

---

## 1. Overview

GitOps treats Git as the single source of truth for infrastructure and application state. Instead of running `helm upgrade` or `kubectl apply` manually, ArgoCD continuously watches the Git repository and reconciles the cluster to match.

### GitOps Flow

```
Developer                    Git Repository              ArgoCD              Kubernetes
   │                              │                        │                     │
   │── Push code ────────────────►│                        │                     │
   │                              │                        │                     │
   │                     CI builds & pushes image          │                     │
   │                              │                        │                     │
   │              Image Updater detects new tag            │                     │
   │                              │                        │                     │
   │                              │◄── Polls for changes ──│                     │
   │                              │                        │                     │
   │                              │── Detects drift ──────►│                     │
   │                              │                        │── Syncs manifests ─►│
   │                              │                        │                     │
   │                              │              ArgoCD applies Kustomize        │
   │                              │                        │── Deploys pods ────►│
```

### Components

- **ArgoCD Application** — Defines what to deploy and where
- **Kustomize** — Base + overlay configuration for environment-specific customization
- **ArgoCD Image Updater** — Automatically updates image tags when new versions are pushed to ECR
- **Sync Waves** — Controls the order of resource application

### Directory Structure

```
phase-07-gitops/
├── argocd/
│   └── application.yaml          # ArgoCD Application manifest
└── kustomize/
    ├── base/
    │   └── kustomization.yaml    # Base resources (shared across environments)
    └── overlays/
        └── production/
            └── kustomization.yaml # Production-specific patches
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| ArgoCD CLI | 2.9+ | `brew install argocd` |
| kubectl | 1.28+ | Installed in Phase 4 |
| Kustomize | 5.x | `brew install kustomize` (also bundled with kubectl) |

### ArgoCD Installation

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Get the initial admin password
argocd admin initial-password -n argocd

# Port-forward to access the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at https://localhost:8080
```

---

## 3. Step-by-Step Implementation

### Step 1: Create the Kustomize Base

The base contains resources shared across all environments:

```bash
cd kustomize/base
```

Create `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../phase-06-kubernetes/helm  # Reference the Helm chart output

commonLabels:
  app.kubernetes.io/managed-by: argocd
  app.kubernetes.io/part-of: ecommerce
```

### Step 2: Create the Production Overlay

The production overlay patches the base with environment-specific settings:

```bash
cd kustomize/overlays/production
```

Create `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

namespace: production

commonLabels:
  environment: production

patches:
  - target:
      kind: Deployment
    patch: |
      - op: replace
        path: /spec/replicas
        value: 3
```

### Step 3: Create the ArgoCD Application

Create `argocd/application.yaml` (see [Configuration Walkthrough](#4-configuration-walkthrough)):

```bash
kubectl apply -f argocd/application.yaml
```

### Step 4: Verify ArgoCD Application

```bash
# Check application status via CLI
argocd app get user-service

# Expected output:
# Name:               user-service
# Project:            ecommerce
# Server:             https://kubernetes.default.svc
# Namespace:          production
# Sync Status:        Synced
# Health Status:      Healthy

# List all applications
argocd app list
```

### Step 5: Install ArgoCD Image Updater

```bash
# Install Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Configure ECR access (create a secret with AWS credentials)
kubectl create secret generic aws-ecr-credentials \
  -n argocd \
  --from-literal=aws.accessKeyId=$AWS_ACCESS_KEY_ID \
  --from-literal=aws.secretAccessKey=$AWS_SECRET_ACCESS_KEY
```

### Step 6: Test the GitOps Flow

```bash
# 1. Make a code change in user-service
# 2. Push to main → CI builds new image and pushes to ECR
# 3. Image Updater detects the new tag
# 4. Image Updater commits the updated tag to the GitOps repo
# 5. ArgoCD detects the change and syncs

# Monitor ArgoCD sync
argocd app get user-service --refresh

# Watch pods rolling update
kubectl get pods -n production -w
```

---

## 4. Configuration Walkthrough

### `argocd/application.yaml` — Line by Line

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: user-service
  namespace: argocd                       # ArgoCD's namespace (not the app namespace)

  annotations:
    # ── ArgoCD Image Updater Configuration ──
    argocd-image-updater.argoproj.io/image-list: app=123456789.dkr.ecr.us-east-1.amazonaws.com/user-service
    # Tells Image Updater which ECR image to watch. "app" is an alias.

    argocd-image-updater.argoproj.io/app.update-strategy: semver
    # Use semantic versioning to determine the latest image.
    # Alternatives: latest, digest, name

    argocd-image-updater.argoproj.io/write-back-method: git
    # When a new image is found, write the updated tag back to Git.
    # This maintains Git as the single source of truth.

  finalizers:
    - resources-finalizer.argocd.argoproj.io
    # Clean up Kubernetes resources when the Application is deleted

spec:
  project: ecommerce                     # ArgoCD project (logical grouping)

  source:
    repoURL: https://github.com/org/ecommerce-gitops
    # The Git repository containing Kustomize manifests

    path: services/user-service/overlays/production
    # Path within the repo to the production overlay

    targetRevision: main
    # Track the main branch

  destination:
    server: https://kubernetes.default.svc
    # Deploy to this Kubernetes cluster (in-cluster)

    namespace: production
    # Target namespace for the resources

  syncPolicy:
    automated:
      prune: true                        # Delete resources removed from Git
      selfHeal: true                     # Revert manual changes made via kubectl

    syncOptions:
      - CreateNamespace=true             # Create the namespace if it doesn't exist
      - PrunePropagationPolicy=foreground # Wait for child resources to be deleted

    retry:
      limit: 5                           # Retry failed syncs up to 5 times
      backoff:
        duration: 5s                     # First retry after 5s
        factor: 2                        # Double the wait each retry (5s, 10s, 20s, 40s, 80s)
        maxDuration: 3m                  # Cap at 3 minutes
```

### Key Behaviors

| Setting | Effect |
|---------|--------|
| `automated.prune: true` | Resources deleted from Git are deleted from the cluster |
| `automated.selfHeal: true` | Manual `kubectl` changes are reverted to match Git |
| `retry.limit: 5` | Transient failures (API server timeouts) are retried automatically |
| `write-back-method: git` | Image tag updates are committed to Git, not just applied to the cluster |

### Kustomize Base vs. Overlay

**Base** (`kustomize/base/kustomization.yaml`):
- Contains the core resource definitions
- Shared across all environments (dev, staging, production)

**Overlay** (`kustomize/overlays/production/kustomization.yaml`):
- Patches the base with production-specific settings
- Higher replica counts, production resource limits, production secrets
- ArgoCD's `source.path` points to the overlay

---

## 5. Verification Checklist

- [ ] ArgoCD is running: `kubectl get pods -n argocd`
- [ ] ArgoCD Application created: `argocd app get user-service`
- [ ] Sync status is "Synced": `argocd app list`
- [ ] Health status is "Healthy": `argocd app list`
- [ ] Auto-sync works: modify Git repo → ArgoCD applies changes within 3 minutes
- [ ] Self-heal works: `kubectl delete pod <pod> -n production` → pod recreated automatically
- [ ] Prune works: remove a resource from Git → ArgoCD deletes it from the cluster
- [ ] Image Updater detects new tags: check Image Updater logs
  ```bash
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater
  ```
- [ ] Kustomize overlay renders correctly: `kustomize build kustomize/overlays/production/`
- [ ] Retry mechanism works: verify retry events in ArgoCD UI

---

## 6. Troubleshooting

### Application stuck in "OutOfSync"

```bash
# Check sync details
argocd app get user-service --show-diff

# Common causes:
# 1. Kustomize build error — test locally:
kustomize build kustomize/overlays/production/

# 2. Resource conflict — another controller managing the same resource
# 3. Webhook validation failing — check admission controller logs
```

### "ComparisonError" in ArgoCD

```bash
# Check ArgoCD application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Common causes:
# 1. Invalid YAML in the Git repository
# 2. CRD not installed in the cluster (e.g., Istio CRDs)
# 3. Kustomize version mismatch
```

### Image Updater not detecting new images

```bash
# Check Image Updater logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Verify ECR access
kubectl get secret aws-ecr-credentials -n argocd

# Check annotation format
kubectl get application user-service -n argocd -o yaml | grep image-updater
```

### Self-heal reverts manual changes too aggressively

```bash
# If you need to temporarily disable self-heal for debugging:
argocd app set user-service --self-heal=false

# Re-enable when done:
argocd app set user-service --self-heal=true
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **ArgoCD vs. Flux** | ArgoCD | Flux CD | Richer UI, Application-of-Apps pattern, wider adoption. Trade-off: heavier resource footprint. |
| **Kustomize vs. Helm in ArgoCD** | Kustomize | Helm directly | Better for environment overlays, no template complexity. Trade-off: Helm's dependency management is lost. |
| **Git write-back** | Enabled | Direct apply | Maintains Git as single source of truth. Trade-off: requires Git write access for Image Updater. |
| **Auto-sync** | Enabled | Manual sync | Fully automated pipeline. Trade-off: changes deploy immediately (mitigated by canary in Phase 11). |
| **Semver update strategy** | Semver | Latest tag | Predictable version ordering. Trade-off: requires proper tagging discipline. |

---

## 8. Production Considerations

- **RBAC** — Configure ArgoCD RBAC policies so developers can view but not modify production applications
- **SSO integration** — Integrate ArgoCD with your identity provider (Okta, GitHub OAuth) for team authentication
- **Application-of-Apps** — Use a parent Application that manages child Applications for each microservice
- **Sync windows** — Define maintenance windows to prevent deployments during peak hours
- **Notifications** — Configure ArgoCD Notifications to send Slack/email alerts on sync status changes
- **Multi-cluster** — ArgoCD can manage multiple clusters from a single control plane
- **Diff customization** — Configure ArgoCD to ignore known diffs (e.g., Istio sidecar injection annotations)

---

## 9. Next Phase

**[Phase 8: Observability & Monitoring →](../phase-08-observability/README.md)**

With GitOps automating deployments, Phase 8 adds full observability — Prometheus for SLI/SLO metrics, Grafana dashboards, Loki for log aggregation, and OpenTelemetry for distributed tracing — so you can monitor the health and performance of every deployment.

---

[← Phase 6: Kubernetes](../phase-06-kubernetes/README.md) | [Back to Project Overview](../README.md) | [Phase 8: Observability →](../phase-08-observability/README.md)
