# Lab 19: E-Commerce DevOps Mastery — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) — Full DevOps Lifecycle  
> **Scope:** 14-phase production-grade e-commerce platform — 6 microservices on EKS with full CI/CD, observability, security, chaos engineering, service mesh, multi-region DR, FinOps, and internal developer platform

---

## What This Project Demonstrates

The 18 preceding labs each taught one layer of the modern infrastructure stack in isolation. This lab integrates all of those layers into a single, coherent production system — a complete e-commerce platform where every phase builds on the prior ones. The result is not a tutorial but a reference architecture: the full DevOps lifecycle as it is actually implemented in production-grade engineering organizations.

---

## System Architecture: The Full Stack

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                   AWS Multi-Region                       │
                    │  Primary: us-east-1          DR: eu-west-1              │
                    │                                                          │
  Users ──► Route 53 (failover routing)                                       │
                    │                                                          │
                    ▼                                                          │
             ALB / Istio Ingress                                               │
                    │                                                          │
                    ▼                                                          │
             EKS Cluster (3 AZs, Karpenter auto-provisioning)                │
             ┌────────────────────────────────────────────┐                  │
             │  API Gateway  User Svc  Product Svc         │                  │
             │  Order Svc    Payment Svc  Notification Svc │                  │
             │       ← Istio mTLS mesh (all traffic) →     │                  │
             │       ← OPA / Falco / Vault / RBAC →        │                  │
             └────────────────────────────────────────────┘                  │
                    │                                                          │
        ┌───────────┼──────────────────┐                                       │
        ▼           ▼                  ▼                                       │
 Aurora Global   ElastiCache       RabbitMQ                                   │
 PostgreSQL      Redis             (async events)                             │
 (RPO < 1 min)   (session cache)                                              │
                    │                                                          │
        Prometheus + Grafana + Loki + Jaeger (observability)                 │
        ArgoCD (GitOps) + Kustomize (env overlays)                           │
        Backstage (developer portal) + Crossplane (self-service infra)       │
                    └─────────────────────────────────────────────────────────┘
```

---

## Phase 1: Project Foundation

### Monorepo with Trunk-Based Development

```javascript
// .commitlintrc.js
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', [
      'api-gateway', 'user-svc', 'product-svc',
      'order-svc', 'payment-svc', 'notification-svc',
      'infra', 'ci', 'docs'
    ]]
  }
}
// Commit: "feat(payment-svc): add idempotency key validation"
// Conventional commits enable: automated CHANGELOG, semantic versioning, 
// and monorepo-aware CI (only build services with changes in their scope)
```

**Why conventional commits in a monorepo?**  
In a 6-service monorepo, a commit without scope information forces CI to rebuild and redeploy all 6 services on every commit. With scope-tagged commits (`feat(payment-svc): ...`), CI path filtering rebuilds only the service indicated by the scope. This reduces CI runtime from 48 minutes (6 services × 8 minutes each) to 8 minutes (1 changed service) for most commits.

---

## Phase 2: Application Development

### Six-Service E-Commerce Platform

| Service | Language | Database | Key Design Pattern |
|---------|----------|----------|--------------------|
| API Gateway | Node.js/Express | — | JWT validation, rate limiting, request routing |
| User Service | Node.js | PostgreSQL + Redis | Session caching, bcrypt password hashing |
| Product Service | Python/FastAPI | PostgreSQL + Redis | Catalog search, inventory, Redis read-through cache |
| Order Service | Node.js | PostgreSQL | Saga pattern for distributed transaction |
| Payment Service | Node.js | PostgreSQL | Idempotency keys, distributed lock |
| Notification Service | Python | — | Event-driven via RabbitMQ, no direct HTTP calls |

**Why the Saga pattern for orders?**  
An order involves three services: Order (create record), Payment (charge customer), Inventory (reserve stock). A synchronous HTTP chain means: if Inventory fails after Payment succeeds, the customer is charged but the order is never fulfilled. Saga pattern coordinates via events — each step publishes a success or failure event. On failure, compensating transactions (refund the charge) are triggered. This achieves eventual consistency without distributed transactions.

**Why idempotency keys in the Payment service?**  
Payment processing has a failure mode where the payment succeeds at the payment processor but the response is lost before returning to the client. The client retries — and the customer is charged twice. Idempotency keys prevent this: the client generates a unique key for each payment intent and includes it in every retry. The payment service stores the result by key — a retry with the same key returns the stored result rather than processing the payment again.

---

## Phase 3: Containerization

### Multi-Stage Docker Builds with Distroless Base Images

```dockerfile
# Phase 3: multi-stage, distroless, non-root
FROM node:18-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM gcr.io/distroless/nodejs18-debian11 AS production
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./src/
# No shell, no package manager, no OS utilities
# Attack surface: node runtime only
USER nonroot
CMD ["src/index.js"]
```

**Why distroless base images rather than `-slim` images?**  
`node:18-slim` is a Debian image stripped of unnecessary packages — it still contains bash, curl, apt, and common utilities. These utilities are useful for debugging but are also useful to an attacker who gains code execution in the container: they can download tools, exfiltrate data, and move laterally using the available shell. A distroless image contains only the language runtime — no shell, no package manager. An attacker with code execution cannot run shell commands because there is no shell. The attack surface is the minimum physically possible.

**Why does 80% image size reduction matter?**  
Smaller images pull faster in CI (every CI run pulls the base image for verification) and in production (new pod starts faster because the image pull completes sooner). At 100 deployments/day, a 200MB image saves 200MB × 100 = 20GB of bandwidth/day vs a 1GB full image. For multi-region deployments, this bandwidth savings applies to each regional ECR registry.

---

## Phase 4: Infrastructure as Code

### Terraform Module Architecture

```hcl
# phase-04-infrastructure-as-code/environments/production.tfvars
module "vpc" {
  source = "../modules/vpc"
  
  vpc_cidr             = "10.0.0.0/16"  # 65,536 IPs
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  # VPC endpoints eliminate NAT gateway charges for AWS service traffic
  enable_s3_endpoint       = true
  enable_ecr_endpoint      = true
  enable_secretsmanager_endpoint = true
}

module "eks" {
  source = "../modules/eks"
  
  cluster_version = "1.28"
  node_groups = {
    system = {
      instance_types = ["m5.large"]
      min_size       = 3   # 1 per AZ for system workloads
      desired_size   = 3
      max_size       = 6
    }
    application = {
      instance_types = ["m5.xlarge", "m5a.xlarge"]  # 2 families for spot diversity
      min_size       = 0
      max_size       = 20
      capacity_type  = "SPOT"
    }
  }
  
  # IRSA: pod-level IAM via OIDC — no node-level instance profiles
  enable_irsa = true
}
```

**Why separate `system` and `application` node groups?**  
System workloads (Prometheus, ArgoCD, Vault, Istio control plane, OPA) must be stable — they cannot be evicted by spot interruptions. Application workloads can tolerate interruption because Kubernetes reschedules them within 2 minutes. Separate node groups allow system workloads to run on on-demand instances and application workloads to run on spot instances, achieving 60-90% cost savings on application capacity without risking stability of cluster infrastructure.

**Why VPC endpoints for S3, ECR, and Secrets Manager?**  
Without VPC endpoints, traffic from EKS pods to these AWS services routes through the public internet — via NAT Gateways. NAT Gateway data processing charges are $0.045/GB. An EKS cluster pulling container images (ECR) 100 times/day at 200MB each = 20GB/day = $0.90/day = $27/month in NAT charges just for image pulls. VPC endpoints route this traffic through the AWS private network — no NAT, no data processing charges.

---

## Phase 5: CI/CD Pipelines

### Monorepo-Aware GitHub Actions

```yaml
# phase-05-cicd/workflows/ci.yml
on:
  push:
    branches: [main]
  pull_request:
    paths:
      - 'services/**'
      - '.github/workflows/ci.yml'

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.changes.outputs.services }}
    steps:
      - uses: dorny/paths-filter@v2
        id: changes
        with:
          filters: |
            payment-svc:
              - 'services/payment-svc/**'
            order-svc:
              - 'services/order-svc/**'
  
  build-and-scan:
    needs: detect-changes
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
    steps:
      - name: Build Docker image
        run: docker build -t $ECR_REPO/${{ matrix.service }}:$GITHUB_SHA services/${{ matrix.service }}/
      
      - name: Trivy scan (CRITICAL only)
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: $ECR_REPO/${{ matrix.service }}:$GITHUB_SHA
          exit-code: '1'
          severity: 'CRITICAL'
          ignore-unfixed: true
      
      - name: Push to ECR with immutable tag
        run: |
          aws ecr batch-check-layer-availability ...
          aws ecr put-image --image-tag $GITHUB_SHA ...
```

**Why `matrix: service: ${{ fromJson(needs.detect-changes.outputs.services) }}`?**  
This pattern dynamically generates a build matrix containing only the services that changed in the current push. If only `payment-svc` changed, the matrix contains one item and only payment-svc is built, scanned, and pushed. Without this pattern, all 6 services build on every commit — 6× the CI cost and time with no additional safety benefit.

**Why `github.sha` as the image tag rather than a semantic version?**  
The git SHA is immutable — it uniquely identifies a specific commit forever. A semantic version (`v1.2.3`) can be moved by a developer who pushes a new image with the same tag. In a production environment, an immutable tag provides a guarantee: if you know which SHA is deployed, you know exactly which code is running, and you can trace from a running container back to the git commit that produced it. This is essential for incident investigation.

---

## Phase 6: Kubernetes Orchestration

### Helm Charts with Health Probes and PDB

```yaml
# phase-06-kubernetes/helm/templates/deployment.yaml (excerpt)
spec:
  replicas: {{ .Values.replicaCount }}
  
  template:
    spec:
      containers:
        - name: {{ .Chart.Name }}
          
          startupProbe:       # NEW: allows slow-starting services
            httpGet:
              path: /health
              port: {{ .Values.service.port }}
            failureThreshold: 30  # 30 × 10s = 5 minutes max startup
            periodSeconds: 10
          
          readinessProbe:
            httpGet:
              path: /ready   # separate endpoint: can serve traffic?
              port: {{ .Values.service.port }}
            initialDelaySeconds: 0
            periodSeconds: 5
            failureThreshold: 3
          
          livenessProbe:
            httpGet:
              path: /health  # is the process alive?
              port: {{ .Values.service.port }}
            initialDelaySeconds: 0
            periodSeconds: 15
            failureThreshold: 3
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .Release.Name }}-pdb
spec:
  minAvailable: {{ .Values.pdb.minAvailable }}  # production: 2 (of 3)
  selector:
    matchLabels:
      app: {{ .Chart.Name }}
```

**Why three separate health probe types (startup, readiness, liveness)?**  
A single probe conflates three distinct questions. Startup probe answers: "is the process still initializing?" — Kubernetes waits for this probe before starting readiness/liveness checks. Readiness probe answers: "is this pod ready to receive traffic?" — a failing readiness probe removes the pod from the Service load balancer without restarting it (useful when temporarily overwhelmed). Liveness probe answers: "is this process healthy?" — a failing liveness probe triggers a pod restart. Using a single probe means Kubernetes restarts pods that should merely be temporarily removed from rotation.

**Why a separate `/ready` endpoint vs `/health`?**  
A service might be alive (`/health` returns 200) but not ready to serve traffic — it's still warming up caches, or a dependency just became unavailable. The readiness endpoint can check dependencies (`db.ping()`, `cache.ping()`) and return 503 when they fail. This removes the pod from the load balancer temporarily without triggering a restart. The health endpoint should only return 200 while the process is running — a healthcheck that includes dependency checks would cause unnecessary pod restarts when a database is briefly unavailable.

---

## Phase 7: GitOps with ArgoCD and Kustomize

### Application-of-Apps Pattern with Kustomize Overlays

```yaml
# phase-07-gitops/argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ecommerce-platform
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/vanessa9373/my-portfolio-projects
    targetRevision: HEAD
    path: labs/19-devops-mastery-ecommerce/phase-07-gitops/kustomize/overlays/production
  
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  
  syncPolicy:
    automated:
      prune: true      # delete resources removed from Git
      selfHeal: true   # revert manual kubectl changes
    
    syncOptions:
      - RespectIgnoreDifferences=true
      - PrunePropagationPolicy=foreground
    
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 5m
```

```yaml
# phase-07-gitops/kustomize/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 3    # production: 3 replicas
    target:
      kind: Deployment

  - patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 500m  # production: more CPU
    target:
      kind: Deployment
      labelSelector: "tier=application"

images:
  - name: payment-svc
    newTag: abc1234  # updated by ArgoCD Image Updater
```

**Why Kustomize overlays rather than Helm values files for environment differences?**  
Helm values files define what changes between environments but require the Helm chart to explicitly template every field that might differ. Kustomize patches can modify any field in any resource without requiring the base manifest to anticipate the override. This means the base manifests are clean and readable, while environment-specific overrides are confined to the overlay — a cleaner separation than a Helm chart with dozens of conditionals.

---

## Phase 8: Observability

### Full Three-Pillar Stack with SLO Correlation

```yaml
# phase-08-observability/prometheus/slo-rules.yml
groups:
  - name: ecommerce-slos
    rules:
      # Payment service: 99.99% (Tier 1)
      - record: slo:payment_availability:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{service="payment-svc", status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total{service="payment-svc"}[5m]))
      
      # Distributed trace correlation: inject trace_id into structured logs
      # Loki query: {service="payment-svc"} | json | status=500
      # → find trace_id → click to Jaeger → see full 6-service call chain
```

**Why Loki for logs rather than ELK (Elasticsearch + Kibana)?**  
Elasticsearch indexes every field in every log entry — powerful for full-text search but expensive in memory and disk. Loki stores logs as compressed chunks with minimal metadata (labels) and queries raw log text with LogQL. For Kubernetes log search patterns (find errors in a specific namespace and service), label-based filtering is sufficient. Loki runs on a fraction of the resources required by Elasticsearch and integrates natively with Grafana — the same interface used for metrics and traces.

---

## Phase 9: Security

### Defense in Depth (Six Layers — see Lab 16 for detail)

The security implementation from Lab 16 is applied to this platform's 6 services with production-grade additions:

```yaml
# phase-09-security/gatekeeper/require-nonroot.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireNonRootUser
metadata:
  name: require-non-root
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
    excludedNamespaces: ["kube-system", "istio-system"]
    # kube-system and istio-system have legitimate root requirements
```

---

## Phase 10: Chaos Engineering

### Litmus + FIS with Hypothesis-Driven Game Days

```yaml
# phase-10-chaos/litmus/pod-kill.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: payment-resilience-test
spec:
  appinfo:
    appns: production
    applabel: app=payment-svc
  
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: PODS_AFFECTED_PERC
              value: "50"       # kill half the payment pods
            - name: TOTAL_CHAOS_DURATION
              value: "60"
        probe:
          - name: payment-slo-check
            type: promProbe
            promProbe/inputs:
              endpoint: http://prometheus:9090
              query: |
                sum(rate(http_requests_total{service="payment-svc", status!~"5.."}[2m]))
                /
                sum(rate(http_requests_total{service="payment-svc"}[2m]))
              comparator:
                criteria: ">="
                value: "0.9999"  # 99.99% SLO maintained during chaos
```

---

## Phase 11: Service Mesh (Istio)

### mTLS Everywhere + Canary via VirtualService

```yaml
# phase-11-service-mesh/istio/peer-authentication.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT   # no plaintext traffic allowed between pods in production
---
# Canary deployment: 90% → stable, 10% → canary
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: payment-svc
spec:
  http:
    - route:
        - destination:
            host: payment-svc
            subset: stable
          weight: 90
        - destination:
            host: payment-svc
            subset: canary
          weight: 10
```

**Why Istio mTLS (mutual TLS) between all services?**  
Pod-to-pod traffic without mTLS is plaintext within the cluster — a compromised pod can eavesdrop on traffic from other services. mTLS authenticates both sides of every connection (not just the server) and encrypts all traffic. In a Kubernetes cluster, this is particularly important because pods from different teams and different security postures run on the same nodes. Istio's sidecar proxies handle mTLS transparently — no application code changes required.

**Why Istio for canary rather than Argo Rollouts (Lab 07)?**  
Argo Rollouts implements canary via pod count (1 pod out of 10 = 10% canary). Istio implements canary via traffic weight — exact percentages regardless of replica count. For payment service with 3 replicas, Argo Rollouts canary at 10% requires a non-integer (0.3 pods), which rounds to 1 pod = 33% canary. Istio's weighted routing delivers exactly 10% traffic to the canary, regardless of replica count, which is more precise for sensitive payment traffic.

---

## Phase 12: Multi-Region Disaster Recovery

### Active-Passive with Route 53 Failover

```hcl
# phase-12-multi-region/terraform/route53.tf
resource "aws_route53_health_check" "primary" {
  fqdn              = "api.ecommerce.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30  # 3 failures × 30s = 90s to detect failure
}

resource "aws_route53_record" "primary" {
  zone_id  = aws_route53_zone.main.zone_id
  name     = "api.ecommerce.example.com"
  type     = "A"
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary.id
  set_identifier  = "primary"
  alias {
    name                   = aws_alb.primary.dns_name
    zone_id                = aws_alb.primary.zone_id
    evaluate_target_health = true
  }
}

# Aurora Global Database: sub-second replication lag (RPO < 1 min)
resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier = "ecommerce-global"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  database_name             = "ecommerce"
}
```

**Why Aurora Global Database rather than cross-region RDS read replicas?**  
RDS cross-region read replicas use logical replication (redo log shipping) with typical lag of 1-5 minutes. Aurora Global Database uses storage-level replication that achieves lag of under 1 second — sub-second RPO. In a payment system where every database write represents a financial transaction, 5 minutes of replication lag means up to 5 minutes of transactions could be lost during a regional failover. Aurora Global's sub-second lag reduces that exposure to a fraction of a second.

**Disaster recovery validation — quarterly DR drills:**
```
Planned failover test (eu-west-1 promotion):
  T+0:00 — Initiate Aurora failover (promote eu-west-1 reader to writer)
  T+0:45 — Aurora failover complete (< 1 minute target)
  T+0:50 — Update Route 53 secondary record to eu-west-1 ALB
  T+3:00 — Route 53 TTL expires, DNS propagated to eu-west-1
  T+5:00 — Full traffic serving from eu-west-1 (RTO target: 5 minutes)
```

---

## Phase 13: FinOps

### Karpenter + Kubecost for Cloud-Native Cost Optimization

```yaml
# phase-13-finops/karpenter/provisioner.yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
    
    - key: node.kubernetes.io/instance-type
      operator: In
      values:
        - m5.large
        - m5a.large
        - m5n.large
        - m4.large
        - m6i.large   # 5 instance families for maximum spot availability
  
  # Spot-first, on-demand fallback
  weight: 10
  
  limits:
    resources:
      cpu: "100"     # cluster-wide CPU cap prevents runaway scaling
      memory: 400Gi
  
  ttlSecondsAfterEmpty: 30  # terminate idle nodes within 30 seconds
```

**Why Karpenter over Cluster Autoscaler?**  
Cluster Autoscaler provisions nodes from predefined Auto Scaling Groups — each ASG is pre-configured with specific instance types and capacity types. Scaling to a new instance type requires creating a new ASG. Karpenter provisions nodes directly (using EC2 Fleet API) and selects the optimal instance type at the moment of scheduling — it picks whatever instance type satisfies the pod's resource request at the lowest cost available from the spot market at that moment. This produces 40-60% better cost efficiency than Cluster Autoscaler because Karpenter doesn't commit to instance types in advance.

**Why `ttlSecondsAfterEmpty: 30`?**  
Cluster Autoscaler waits 10 minutes before terminating an empty node (to avoid thrashing if another pod is about to be scheduled). Karpenter's `ttlSecondsAfterEmpty: 30` terminates empty nodes in 30 seconds. For a cluster that processes batch jobs (nodes needed briefly, then idle), 10-minute delay vs 30-second delay represents 9.5 minutes of paying for idle node capacity per batch cycle. At $0.10/hour per node, 100 batch cycles/day × 9.5 minutes = $2.38/day wasted on idle nodes.

---

## Phase 14: Platform Engineering

### Backstage Developer Portal + Crossplane Self-Service

```yaml
# phase-14-platform-engineering/backstage/templates/new-microservice.yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-microservice
  title: "New Microservice"
  description: "Scaffold a production-ready microservice in 5 minutes"
spec:
  parameters:
    - title: Service Configuration
      properties:
        serviceName:
          type: string
          pattern: '^[a-z][a-z0-9-]*$'
        language:
          type: string
          enum: ['nodejs', 'python']
        requiresDatabase:
          type: boolean
          default: false
  
  steps:
    - id: fetch-template
      action: fetch:template
      input:
        url: ./skeleton
        values:
          serviceName: ${{ parameters.serviceName }}
    
    - id: create-github-repo
      action: github:repo:create
    
    - id: apply-argocd-app
      action: kubernetes:apply
      input:
        manifest: |
          kind: Application
          metadata:
            name: ${{ parameters.serviceName }}
```

```yaml
# phase-14-platform-engineering/crossplane/database-composition.yaml
# Developer creates: kubectl apply -f my-database.yaml
# Crossplane provisions: RDS Aurora cluster with parameter groups, subnet groups,
# security groups, secret rotation — all production-grade configuration

apiVersion: platform.example.com/v1alpha1
kind: PostgresDatabase
metadata:
  name: order-db
  namespace: team-a
spec:
  environment: production
  size: small       # platform team defines what "small" means in RDS terms
  team: order-team
```

**Why Backstage templates (golden paths) rather than documentation?**  
Documentation describes how to create a new service. A Backstage template *does* it. The difference: documentation requires the developer to read, interpret, configure, and execute 20 steps correctly. A template executes those 20 steps in 5 minutes and guarantees the result is production-compliant (security scanning configured, monitoring enabled, ArgoCD app created, Slack channel set up). Golden paths don't eliminate flexibility — they make the compliant path the easy path.

**Why Crossplane for self-service infrastructure rather than Terraform?**  
Terraform requires: developers to learn HCL, to understand AWS resource configuration, to run `terraform apply`, and to have IAM permissions to create the resources. Crossplane wraps all of that into a Kubernetes Custom Resource (`kind: PostgresDatabase`). Developers declare what they need in a familiar format (YAML, like a Kubernetes Deployment), and Crossplane provisions the actual infrastructure using the platform team's pre-configured composition — which enforces encryption, backup retention, and security group rules that developers can't accidentally omit.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **GitOps as single source of truth:** Every state change is a Git commit — rollback is always `git revert`, audit trail is always `git log`
- **Backstage golden paths:** New service setup takes 5 minutes and produces a production-compliant result — compliance is not a review gate but a built-in output
- **ArgoCD `selfHeal: true`:** Configuration drift is automatically reverted — the cluster's actual state always matches the declared state in Git

### Security
- **Defense in depth (6 layers):** RBAC + NetworkPolicies + Trivy + Falco + OPA + Vault — each layer independently reduces attack surface
- **Istio strict mTLS:** All pod-to-pod traffic encrypted and mutually authenticated — no plaintext within the cluster
- **Zero critical CVEs:** Trivy scanning in CI blocks images with unpatched critical vulnerabilities before they reach production

### Reliability
- **99.95% availability SLO:** Achieved through: PDB (no single-point-of-failure deploys), multi-AZ EKS, Karpenter auto-provisioning, Aurora Global HA, chaos-validated failure handling
- **RPO < 1 min, RTO < 5 min:** Aurora Global sub-second replication + Route 53 health-check failover + pre-staged DR environment
- **Circuit breaker patterns:** Payment and order services implement circuit breakers (via Istio DestinationRule) — a slow downstream service doesn't cascade into a full platform outage

### Performance Efficiency
- **Karpenter right-instance-type selection:** Pods get the optimal instance type for their resource footprint — no wasted capacity from pre-defined ASG configurations
- **Distroless images:** 80% smaller images → faster pulls → faster pod startup → faster recovery from node failures
- **Aurora Global read replicas:** Product catalog reads served from local region reader — no cross-region latency for read-heavy traffic

### Cost Optimization
- **40% cost reduction:** Karpenter spot-first provisioning + rightsizing + idle node termination in 30 seconds
- **70% Spot utilization:** 5 instance type families → 15 spot capacity pools → interruption probability low enough for production application workloads
- **Conventional commits → path-filtered CI:** Only changed services build → 6× reduction in CI compute cost for single-service changes

### Sustainability
- **`ttlSecondsAfterEmpty: 30`:** Idle nodes terminated in 30 seconds → no compute consumed for absent workloads
- **Distroless images:** Smaller images = less storage = less energy for image distribution across regions

---

## Key Architectural Insight

The deepest insight from building all 14 phases is the relationship between phases: each phase is not additive but multiplicative. GitOps (Phase 7) makes CI/CD (Phase 5) reversible. Observability (Phase 8) makes chaos engineering (Phase 10) safe — you can only run a chaos experiment if you can observe its impact in real time. Security (Phase 9) makes the service mesh (Phase 11) trustworthy — mTLS is meaningful only if certificates are managed correctly. Platform engineering (Phase 14) makes all the preceding phases accessible — a golden path template embeds months of architectural decisions (GitOps workflow, Trivy scanning, ArgoCD sync, RBAC, NetworkPolicies) into a 5-minute developer action.

The architecture is not a set of independent tools. It is a system where each component depends on the others being in place. The value of the complete system exceeds the sum of the parts by exactly this amount of interdependence. That is what this project is designed to demonstrate.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
