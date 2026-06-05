# Phase 6: Kubernetes Orchestration

**Difficulty:** Intermediate | **Time:** 5-7 hours | **Prerequisites:** Phase 5

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

This phase deploys the 6 microservices to the EKS cluster using a shared Helm chart. Instead of creating separate charts per service, a single parameterized chart is used with per-service values files. This approach keeps configurations DRY while allowing service-specific customization.

### What the Helm Chart Provides

- **Deployment** — Rolling updates with configurable replicas and resource limits
- **Service** — ClusterIP services for internal service discovery
- **HPA** — Horizontal Pod Autoscaler with CPU and memory targets
- **PDB** — Pod Disruption Budget for safe node maintenance
- **Ingress** — Istio-based ingress routing
- **Service Account** — IRSA integration for AWS API access from pods

### Helm Chart Structure

```
phase-06-kubernetes/
└── helm/
    ├── Chart.yaml                # Chart metadata
    ├── templates/
    │   ├── deployment.yaml       # Pod specification
    │   ├── service.yaml          # ClusterIP service
    │   ├── hpa.yaml             # Horizontal Pod Autoscaler
    │   ├── pdb.yaml             # Pod Disruption Budget
    │   ├── ingress.yaml         # Istio ingress rules
    │   └── serviceaccount.yaml  # IRSA service account
    └── values/
        └── production.yaml       # Production configuration
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Helm | 3.13+ | `brew install helm` |
| kubectl | 1.28+ | `brew install kubectl` |
| AWS CLI | 2.x | Installed in Phase 4 |

### Cluster Access

```bash
# Verify kubectl is configured for the EKS cluster
kubectl cluster-info
kubectl get nodes

# Expected: 5 nodes in Ready state
```

---

## 3. Step-by-Step Implementation

### Step 1: Create the Helm Chart

```bash
cd phase-06-kubernetes/helm
```

Create `Chart.yaml`:

```yaml
apiVersion: v2
name: ecommerce-service
description: Shared Helm chart for e-commerce microservices
type: application
version: 0.1.0
appVersion: "1.0.0"
```

### Step 2: Create the Deployment Template

The deployment template (`templates/deployment.yaml`) defines how pods are created and managed. Key features:
- Rolling update strategy with `maxSurge: 1` and `maxUnavailable: 0` for zero-downtime deployments
- Liveness, readiness, and startup probes for health monitoring
- Resource requests and limits for proper scheduling
- Pod anti-affinity to spread replicas across AZs
- IRSA service account mounting for AWS API access

### Step 3: Create the HPA Template

The HPA template (`templates/hpa.yaml`) enables automatic scaling based on metrics:

```yaml
# Dual-metric autoscaling: CPU AND memory
# Scale out when CPU > 70% OR memory > 80%
# Scale in when both are below thresholds
targetCPUUtilization: 70       # Scale up when average CPU exceeds 70%
targetMemoryUtilization: 80    # Scale up when average memory exceeds 80%
minReplicas: 3                 # Never scale below 3 (one per AZ)
maxReplicas: 20                # Scale ceiling
```

### Step 4: Create the PDB Template

The PDB template (`templates/pdb.yaml`) ensures availability during node maintenance:

```yaml
# At least 2 pods must remain running during voluntary disruptions
# (node drain, rolling update, cluster upgrade)
minAvailable: 2
```

### Step 5: Create Production Values

Create `values/production.yaml` with production-specific settings (see [Configuration Walkthrough](#4-configuration-walkthrough) for details).

### Step 6: Deploy a Service

```bash
# Dry run to verify the rendered templates
helm template user-service ./helm \
  -f helm/values/production.yaml \
  --set image.repository=123456789.dkr.ecr.us-east-1.amazonaws.com/user-service \
  --set image.tag=abc123

# Install the release
helm upgrade --install user-service ./helm \
  -f helm/values/production.yaml \
  --namespace production \
  --create-namespace \
  --set image.tag=$(git rev-parse --short HEAD)

# Verify the deployment
kubectl get pods -n production -l app=user-service
```

**Expected output:**

```
NAME                            READY   STATUS    RESTARTS   AGE
user-service-6d5b8c9f4-abc12   2/2     Running   0          30s
user-service-6d5b8c9f4-def34   2/2     Running   0          30s
user-service-6d5b8c9f4-ghi56   2/2     Running   0          30s
```

### Step 7: Deploy All Services

```bash
# Deploy each service with its specific overrides
for SERVICE in api-gateway user-service product-service order-service payment-service notification-service; do
  helm upgrade --install $SERVICE ./helm \
    -f helm/values/production.yaml \
    --namespace production \
    --set image.repository=123456789.dkr.ecr.us-east-1.amazonaws.com/$SERVICE \
    --set image.tag=$(git rev-parse --short HEAD) \
    --set service.port=3000
done
```

### Step 8: Verify All Resources

```bash
# Check all deployments
kubectl get deployments -n production

# Check HPA status
kubectl get hpa -n production

# Check PDB status
kubectl get pdb -n production

# Check services
kubectl get svc -n production
```

---

## 4. Configuration Walkthrough

### `values/production.yaml` — Section by Section

#### Replicas and Image

```yaml
replicaCount: 3                    # Start with 3 replicas (one per AZ)

image:
  repository: 123456789.dkr.ecr.us-east-1.amazonaws.com/user-service
  pullPolicy: IfNotPresent         # Use cached image if available
```

#### IRSA Service Account

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/user-service-role
    # IRSA: Kubernetes service account → IAM role mapping
    # Pods can access AWS APIs (S3, SQS, Secrets Manager) without static credentials
```

#### Resource Management

```yaml
resources:
  requests:
    cpu: 250m               # 25% of a CPU core — used for scheduling decisions
    memory: 256Mi            # 256 MB — guaranteed allocation
  limits:
    cpu: 500m               # 50% of a CPU core — hard ceiling
    memory: 512Mi            # 512 MB — OOMKilled if exceeded
```

- **Requests** — What Kubernetes guarantees. Used for scheduling decisions.
- **Limits** — Maximum allowed. CPU is throttled; memory triggers OOMKill.

#### Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 3             # Never scale below 3 (availability guarantee)
  maxReplicas: 20            # Scale ceiling for peak traffic
  targetCPUUtilization: 70   # Scale out when average CPU > 70%
  targetMemoryUtilization: 80 # Scale out when average memory > 80%
```

Dual-metric HPA: scales on whichever threshold is breached first. This prevents both CPU saturation (slow responses) and memory pressure (OOMKills).

#### Pod Disruption Budget

```yaml
podDisruptionBudget:
  minAvailable: 2            # At least 2 pods must remain running
                              # During node drain, upgrade, or voluntary disruption
```

With `minReplicas: 3` and `minAvailable: 2`, only 1 pod can be disrupted at a time during maintenance.

#### Health Probes

```yaml
probes:
  liveness:
    path: /health/live             # Is the process alive?
    initialDelaySeconds: 10        # Wait 10s before first check
    periodSeconds: 15              # Check every 15s
    failureThreshold: 3            # Restart after 3 consecutive failures
  readiness:
    path: /health/ready            # Can it accept traffic?
    initialDelaySeconds: 5         # Check sooner than liveness
    periodSeconds: 10              # Check every 10s
    failureThreshold: 3            # Remove from service after 3 failures
  startup:
    path: /health/live             # Has it started?
    initialDelaySeconds: 0
    periodSeconds: 5
    failureThreshold: 30           # Allow up to 150s (30 × 5s) for startup
```

- **Startup probe** runs first — gives slow-starting apps time to initialize without being killed by the liveness probe
- **Readiness probe** controls traffic routing — failing readiness removes the pod from the Service endpoints
- **Liveness probe** detects deadlocks — failing liveness restarts the pod

#### Ingress

```yaml
ingress:
  enabled: true
  className: istio                 # Use Istio ingress controller
  hosts:
    - host: api.ecommerce.example.com
      paths:
        - path: /api/users
          pathType: Prefix         # Match /api/users and /api/users/*
```

#### Pod Anti-Affinity

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - user-service
          topologyKey: topology.kubernetes.io/zone
```

This spreads pods across AZs. If the scheduler can, it places each `user-service` replica in a different AZ. `preferred` (not `required`) means it won't block scheduling if AZs are unbalanced.

---

## 5. Verification Checklist

- [ ] Helm chart lints cleanly: `helm lint ./helm -f helm/values/production.yaml`
- [ ] Template renders correctly: `helm template test ./helm -f helm/values/production.yaml`
- [ ] All 6 services deployed: `kubectl get deployments -n production`
- [ ] All pods Running with 2/2 Ready (app + Istio sidecar): `kubectl get pods -n production`
- [ ] HPA is active for all services: `kubectl get hpa -n production`
- [ ] PDB is configured: `kubectl get pdb -n production`
- [ ] Services are accessible via ClusterIP: `kubectl get svc -n production`
- [ ] Health probes passing: `kubectl describe pod <pod-name> -n production` shows no probe failures
- [ ] Pods spread across AZs: `kubectl get pods -o wide -n production` shows different nodes
- [ ] IRSA working: pod can access AWS APIs without static credentials

---

## 6. Troubleshooting

### Pods stuck in Pending

```bash
kubectl describe pod <pod-name> -n production

# Common causes:
# 1. Insufficient cluster resources — check node capacity
kubectl top nodes

# 2. Node selector doesn't match any nodes
kubectl get nodes --show-labels | grep role=general

# 3. PDB blocking eviction — check PDB status
kubectl get pdb -n production
```

### Pods in CrashLoopBackOff

```bash
# Check application logs
kubectl logs <pod-name> -n production

# Check previous crash logs
kubectl logs <pod-name> -n production --previous

# Common causes:
# 1. Missing environment variables (DATABASE_URL, etc.)
# 2. Cannot connect to database/Redis
# 3. Health probe path returns non-200
```

### HPA not scaling

```bash
# Check if metrics-server is running
kubectl get pods -n kube-system | grep metrics-server

# Check current metrics
kubectl top pods -n production

# Check HPA events
kubectl describe hpa <service-name> -n production
```

### Image pull errors

```bash
# Verify ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# Verify image exists
aws ecr describe-images --repository-name user-service --query 'imageDetails[0].imageTags'
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Shared chart vs. chart per service** | Shared chart | Individual charts per service | DRY — one template set, parameterized via values. Trade-off: complex conditional logic if services diverge significantly. |
| **HPA dual metrics** | CPU + Memory | CPU only / custom metrics | Catches both compute-bound and memory-bound saturation. Trade-off: more complex tuning. |
| **PDB minAvailable** | `minAvailable: 2` | `maxUnavailable: 1` | Explicit guarantee of available capacity. Trade-off: identical effect with 3 replicas. |
| **Preferred anti-affinity** | Preferred | Required | Won't block scheduling if AZs are imbalanced. Trade-off: pods might colocate under pressure. |
| **ClusterIP services** | ClusterIP | NodePort / LoadBalancer | Internal-only access; external routing handled by Istio Ingress (Phase 11). Trade-off: requires ingress controller. |

---

## 8. Production Considerations

- **Resource tuning** — Monitor actual CPU/memory usage with Prometheus (Phase 8) and adjust requests/limits based on P99 consumption
- **VPA** — Consider Vertical Pod Autoscaler for automatic right-sizing recommendations
- **Pod topology spread** — In addition to anti-affinity, consider `topologySpreadConstraints` for more even distribution
- **Priority classes** — Define `PriorityClass` resources so critical services (API Gateway, Payment) are scheduled before others during resource contention
- **External Secrets** — Use External Secrets Operator or Vault CSI driver (Phase 9) instead of Kubernetes Secrets for database credentials
- **Init containers** — Add init containers for database migration or dependency health checks before the main container starts

---

## 9. Next Phase

**[Phase 7: GitOps & Continuous Delivery →](../phase-07-gitops/README.md)**

With Helm charts defining the desired state, Phase 7 introduces ArgoCD for GitOps-based deployment — the cluster continuously reconciles to match the Git repository, with automatic sync, self-healing, and image tag updates.

---

[← Phase 5: CI/CD Pipelines](../phase-05-cicd/README.md) | [Back to Project Overview](../README.md) | [Phase 7: GitOps →](../phase-07-gitops/README.md)
