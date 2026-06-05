# EKS Online Boutique — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** End-to-end DevOps lifecycle — Infrastructure provisioning → CI/CD → GitOps deploy → Observability → Security

---

## What This Architecture Demonstrates

Most portfolio projects deploy a single service. This project deploys 11 real microservices written in 5 languages (Go, Python, Java, C#, Node.js) on AWS EKS with every production DevOps pattern implemented: GitOps, observability, container security scanning, node autoscaling, and secrets management. The goal is to demonstrate the complete engineering lifecycle — not just the infrastructure.

---

## Architecture Overview

```
                         Internet
                             │
                        [Route 53]   ← DNS resolution
                             │
                        [ACM + ALB]  ← TLS termination, HTTPS ingress
                             │
            ┌────────────────────────────────────────┐
            │            AWS VPC (3 AZs)             │
            │                                        │
            │  Public Subnets                        │
            │  ├── NAT Gateways (one per AZ)         │
            │  └── ALB nodes                         │
            │                                        │
            │  Private Subnets                       │
            │  └── EKS Worker Nodes (Karpenter)      │
            │      ├── frontend (Go)                 │
            │      ├── cartservice (C#)              │
            │      ├── checkoutservice (Go)          │
            │      ├── paymentservice (Node.js)      │
            │      ├── productcatalogservice (Go)    │
            │      ├── currencyservice (Node.js)     │
            │      ├── shippingservice (Go)          │
            │      ├── emailservice (Python)         │
            │      ├── recommendationservice (Python)│
            │      ├── adservice (Java)              │
            │      └── loadgenerator (Python/Locust) │
            └────────────────────────────────────────┘
                             │
Supporting Layer:
├── ECR (11 repos) ← container images
├── GitHub Actions ← CI pipeline
├── ArgoCD ← GitOps operator
├── Prometheus ← metrics
├── Grafana ← dashboards
├── CloudWatch ← AWS-native logs
└── Secrets Manager ← secrets (via ESO)
```

---

## Phase 1: Infrastructure Provisioning (Terraform)

### Step 1 — VPC with 3-AZ Architecture

Terraform provisions a VPC (`10.0.0.0/16`) with 6 subnets across 3 availability zones.

**Subnet design:**

```
AZ us-east-1a:
  Public:  10.0.1.0/24   ← NAT Gateway, ALB nodes
  Private: 10.0.10.0/24  ← EKS worker nodes

AZ us-east-1b:
  Public:  10.0.2.0/24
  Private: 10.0.11.0/24

AZ us-east-1c:
  Public:  10.0.3.0/24
  Private: 10.0.12.0/24
```

**Why 3 AZs?**  
An AZ is an independent data center. If a single AZ experiences a power or networking outage, workloads spread across 3 AZs continue operating with 2/3 capacity. AWS SLA guarantees: "Services will be available in at least 2 AZs per region during any given AZ failure." 3 AZs means surviving an AZ failure without breaching a 99.9% availability SLA.

**Why private subnets for EKS nodes?**  
Worker nodes in public subnets receive public IP addresses by default — they are directly reachable from the internet. A misconfigured security group or exposed NodePort would be immediately exploitable. Private subnets have no internet-accessible IPs. All external traffic reaches the cluster through the ALB (which is the only public-facing component). Node-to-internet traffic (pulling ECR images, calling AWS APIs) goes through NAT Gateways in the public subnets.

**Why NAT Gateway per AZ instead of a single NAT Gateway?**  
A single NAT Gateway is a single point of failure. If the NAT Gateway's AZ fails, worker nodes in the other two AZs lose internet connectivity — they cannot pull new container images or reach AWS APIs (ECR, Secrets Manager, CloudWatch). One NAT Gateway per AZ (3 total) costs ~$135/month vs ~$45/month for a single NAT, but eliminates the cross-AZ single point of failure. For a production cluster, this is the correct trade-off.

**VPC Flow Logs** are enabled, delivering to CloudWatch Logs. Flow Logs record accepted and rejected traffic at the ENI level — essential for:
- Security investigation (detect lateral movement, unexpected inter-service traffic)
- Network troubleshooting (confirm traffic is reaching the correct subnet/security group)
- Compliance (network access logs for SOC 2 audit)

### Step 2 — EKS Cluster Provisioning

Terraform's `modules/eks/` provisions:

```hcl
resource "aws_eks_cluster" "main" {
  name    = "online-boutique"
  version = "1.28"
  
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true  # restricted to corporate CIDR
    public_access_cidrs     = ["203.0.113.0/32"]  # operator IP range
  }
}
```

**Why Kubernetes 1.28?**  
AWS EKS supports N, N-1, and N-2 minor versions. 1.28 is a recent stable release with production stability (not the cutting-edge release, which may have less mature tooling). Using the latest stable version also means security patches are available for the longest remaining support window before forced upgrade.

**OIDC Provider for IRSA:**  
The EKS cluster creates an OIDC identity provider. This enables IAM Roles for Service Accounts (IRSA) — the mechanism by which individual Kubernetes service accounts receive specific AWS permissions.

**Why IRSA instead of EC2 instance roles?**  
Without IRSA: all pods on a worker node share the node's EC2 instance role. If the `emailservice` pod needs SES permissions, every pod on that node gets SES permissions — including the `adservice` and `currencyservice` which have no business calling SES.

With IRSA: each service account has its own IAM role with minimum required permissions. The OIDC trust policy restricts assumption to a specific Kubernetes namespace + service account combination:

```json
{
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/id/XXXX:sub": 
        "system:serviceaccount:default:order-processor"
    }
  }
}
```

Only the `order-processor` service account in the `default` namespace can assume the role — not any other pod, not even a pod with a compromised service account in a different namespace.

### Step 3 — ECR Repositories (11 repos, one per service)

Each service has a dedicated ECR repository with:

```hcl
resource "aws_ecr_repository" "services" {
  for_each             = toset(var.service_names)
  name                 = each.key
  image_tag_mutability = "IMMUTABLE"  # tags cannot be overwritten
  
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "cleanup" {
  repository = aws_ecr_repository.services[each.key].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
```

**Why `IMMUTABLE` tags?**  
Tag mutability means `git push` can overwrite the `latest` tag in ECR with a different image. If ArgoCD is deploying `image: ecr/frontend:latest`, a push of a broken image immediately affects running pods. Immutable tags mean `frontend:abc1234` always refers to the exact image built at that commit. Tags cannot be reassigned — if you need to deploy a fix, you build a new image with a new tag.

**Why lifecycle policy for 10 images?**  
ECR charges $0.10/GB/month. Storing 100 image versions (each 200MB) = $2/repo/month × 11 repos = $22/month in ECR storage. Keeping the 10 most recent images (~$2.20/month total) provides rollback capability for recent deploys while avoiding unbounded storage growth.

---

## Phase 2: CI/CD Pipeline (GitHub Actions)

### Step 4 — Developer Pushes Code to `main`

GitHub Actions workflow triggers on push. The pipeline has three parallel stages:

```yaml
jobs:
  detect-changes:
    outputs:
      changed_services: ${{ steps.detect.outputs.services }}
  
  build-and-scan:
    needs: detect-changes
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.changed_services) }}
    steps:
      - name: Build Docker image
        run: docker build -t $ECR_REGISTRY/$SERVICE:$GITHUB_SHA services/$SERVICE/
      
      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: $ECR_REGISTRY/$SERVICE:$GITHUB_SHA
          exit-code: '1'           # ← fail the job on findings
          severity: 'CRITICAL'     # ← only block on CRITICAL CVEs
      
      - name: Push to ECR
        run: |
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker push $ECR_REGISTRY/$SERVICE:$GITHUB_SHA
      
      - name: Update manifest
        run: |
          sed -i "s|image: $ECR_REGISTRY/$SERVICE:.*|image: $ECR_REGISTRY/$SERVICE:$GITHUB_SHA|" \
            kubernetes-manifests/$SERVICE/deployment.yaml
          git commit -am "ci: update $SERVICE to $GITHUB_SHA"
          git push
```

### Step 5 — OIDC Authentication (No AWS Keys in GitHub)

```yaml
permissions:
  id-token: write  # required for OIDC token generation
  contents: read

steps:
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789:role/github-actions-role
      aws-region: us-east-1
```

**OIDC trust policy on the IAM role:**
```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:vanessa9373/portfolio-devops-project:ref:refs/heads/main"
    }
  }
}
```

Only workflows running on the `main` branch of the specific repository can assume this role. A fork, a branch, or a different workflow cannot. The temporary credentials (1-hour TTL) have permissions scoped to ECR push only — `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`.

### Step 6 — Trivy Container Scanning

Trivy scans the built image against multiple vulnerability databases:

- **NVD (National Vulnerability Database):** CVEs for OS packages (apt/apk/yum)
- **GitHub Advisory Database:** CVEs for language packages (pip, npm, Maven, NuGet)
- **RedHat, Alpine, Debian security advisories:** Distro-specific advisories

**Why block on CRITICAL only, not HIGH?**

CRITICAL CVEs have a CVSS score ≥ 9.0 and typically represent: remote code execution, authentication bypass, or privilege escalation with a known exploit. Blocking these is unambiguously correct.

HIGH CVEs (CVSS 7.0–8.9) include important but exploitable-only-under-specific-conditions vulnerabilities. Many HIGH CVEs in base OS images are theoretical — the affected component isn't reachable in the application's execution path. Blocking on HIGH would produce frequent false positives that erode trust in the security gate ("the pipeline failed again for a curl vulnerability that isn't called by any service code") and create pressure to bypass the gate entirely.

The pragmatic approach: CRITICAL = hard block. HIGH = alert the security team for review. LOW/MEDIUM = logged for awareness, no action required.

**Why CI scanning instead of runtime scanning?**

Scanning at build time (before ECR push):
- Catches vulnerabilities before they ever reach ECR or the cluster
- Zero runtime overhead — scanning doesn't affect running containers
- Fast feedback loop — developer knows about the issue while they still have context

Runtime scanning (e.g., Falco, Sysdig):
- Detects vulnerabilities introduced after deployment (new CVE disclosures)
- Detects anomalous behavior (unexpected outbound connections, file writes)
- Higher operational cost

Both are valuable. CI scanning is the first line of defense. This project implements CI scanning + ECR scan on push (AWS native) as the baseline, with Falco as a future enhancement.

---

## Phase 3: GitOps with ArgoCD

### Step 7 — ArgoCD Detects Manifest Diff

After the CI pipeline updates the manifest in Git (Step 5), ArgoCD detects the diff within its poll interval (default: 3 minutes, or webhook-triggered for near-instant sync).

**ArgoCD Application CRD:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: frontend
spec:
  project: online-boutique
  source:
    repoURL: https://github.com/vanessa9373/portfolio-devops-project
    targetRevision: HEAD
    path: kubernetes-manifests/frontend
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true      # delete resources removed from Git
      selfHeal: true   # revert manual kubectl changes
```

**Why `selfHeal: true`?**  
Without self-healing, an operator who runs `kubectl set image deployment/frontend frontend=<emergency-image>` would create drift between Git (the source of truth) and the cluster. The next ArgoCD sync would revert the manual change, which is the desired behavior — Git is authoritative. This also means manual `kubectl` changes are always reverted, enforcing GitOps discipline.

**Why `prune: true`?**  
If a service is removed from `kubernetes-manifests/`, ArgoCD deletes the corresponding Kubernetes resources. Without pruning, removed services continue running in the cluster — consuming resources and potentially creating security exposure for unmaintained code.

### Step 8 — ArgoCD Syncs to EKS Cluster

ArgoCD applies the updated manifests to the cluster via the Kubernetes API server:

```
ArgoCD (running in argocd namespace)
    │ kubectl apply (using ArgoCD's service account with RBAC)
    │
Kubernetes API Server
    │
etcd (desired state stored)
    │
kube-scheduler → assigns pods to nodes
    │
kubelet (on each node) → pulls image from ECR, starts container
```

**Rollback mechanism:** `git revert HEAD` on the `kubernetes-manifests/` directory creates a new commit that reverts the image tag to the previous version. ArgoCD detects the new HEAD and syncs — no special ArgoCD commands, no `kubectl rollout undo`, no flags to remember. The rollback is a Git operation, auditable in Git history, reversible if the revert itself was a mistake.

### Step 9 — Karpenter Provisions Nodes On-Demand

When new pods are scheduled after a deploy, Kubernetes marks them as `Pending` if no node has available resources.

**Karpenter provisioner:**
```yaml
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
      values: ["m5.xlarge", "m5.2xlarge", "c5.xlarge", "c5.2xlarge"]
  limits:
    resources:
      cpu: 100
  providerRef:
    name: default
  ttlSecondsAfterEmpty: 30  # terminate idle nodes after 30 seconds
```

**How Karpenter decides which instance type to launch:**

1. Karpenter examines all pending pods' resource requests (`requests.cpu`, `requests.memory`)
2. Evaluates the `Provisioner` requirements (allowed instance types, capacity types)
3. Selects the most cost-efficient instance type that fits all pending pods
4. Calls EC2 `RunInstances` directly (no Auto Scaling Group in the loop)
5. Node joins the cluster and pods schedule in < 60 seconds total

**Why Karpenter over Cluster Autoscaler:**

Cluster Autoscaler requires pre-defined node groups. If you have a `m5.xlarge` node group and a `c5.2xlarge` node group, and the pending pods fit better on `c5.2xlarge`, Cluster Autoscaler adds a node from each group and you decide which to scale. It also takes 3–5 minutes to provision a node (ASG launch → EC2 start → node registration → kubelet ready).

Karpenter bypasses the ASG and selects the optimal instance type dynamically — it provisions the right instance, not a pre-selected instance group. Sub-60-second provisioning means pods start faster; dynamic instance selection means no idle node group capacity.

**~30% cost reduction** comes from:
- Spot instances for stateless services (frontend, catalog, recommendation) — Spot is 60–90% cheaper than on-demand
- Node consolidation: `ttlSecondsAfterEmpty: 30` terminates idle nodes within 30 seconds
- Bin-packing: Karpenter computes the minimum node size that fits all pending pods — no over-provisioning

---

## Phase 4: Observability Stack

### Step 10 — Prometheus Metrics Collection

Prometheus is deployed via Helm (`kube-prometheus-stack`) and scrapes metrics from:

**Service monitors (application metrics):**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: frontend
spec:
  selector:
    matchLabels:
      app: frontend
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Each Go and Python service exposes Prometheus metrics at `/metrics`. Prometheus scrapes every 15 seconds.

**Key metrics per service:**

| Metric | Type | What It Measures |
|--------|------|-----------------|
| `http_request_duration_seconds` | Histogram | p50/p95/p99 latency per endpoint |
| `http_requests_total` | Counter | Request rate + error rate |
| `go_goroutines` | Gauge | Goroutine leak detection (Go services) |
| `jvm_memory_used_bytes` | Gauge | JVM heap pressure (adservice, Java) |
| `process_resident_memory_bytes` | Gauge | Container memory usage |

**Why Prometheus over CloudWatch metrics?**  
CloudWatch can collect container metrics via Container Insights, but:
- CloudWatch custom metrics cost $0.30/metric/month — at 50 metrics × 11 services = $165/month
- Prometheus is free once the cluster is running
- PromQL (Prometheus Query Language) is more expressive than CloudWatch's metrics math for complex queries like p99 latency over a 5-minute rolling window
- The Prometheus ecosystem (AlertManager, Grafana, Thanos) integrates tightly

CloudWatch Container Insights is still used for CloudWatch-native alerting (e.g., ALB 5xx rate → SNS → PagerDuty) and for log aggregation where Prometheus doesn't apply.

### Step 11 — Grafana Dashboards

Grafana connects to Prometheus as a datasource and provides dashboards for:

**Cluster overview:** Node CPU/memory utilization, pod count by namespace, Karpenter node events

**Per-service golden signals (4 signals per service):**
- Latency: `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` — p99 latency
- Traffic: `rate(http_requests_total[5m])` — requests per second
- Errors: `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])` — error rate
- Saturation: CPU and memory usage relative to requested resources

**Why these 4 signals?** The "four golden signals" (from Google's SRE book) capture every dimension of service health visible from outside. Latency tells you user experience. Traffic tells you demand. Errors tell you reliability. Saturation tells you capacity. Any production incident will manifest in one or more of these.

**AlertManager rules:**
```yaml
- alert: HighLatencyP99
  expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="frontend"}[5m])) > 0.5
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Frontend p99 latency above 500ms for 5 minutes"

- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
  for: 5m
  labels:
    severity: critical
```

Alerts fire to AlertManager → Slack (warning) or PagerDuty (critical).

### Step 12 — AWS X-Ray Distributed Tracing

X-Ray traces are collected for the checkout flow — the most complex service-to-service call chain:

```
frontend → checkoutservice → (paymentservice + shippingservice + emailservice)
                                    │
                              cartservice → Redis
                                    │
                             productcatalogservice
```

X-Ray shows the complete trace: total checkout latency, which service is the bottleneck, and where errors occur in the call chain. If checkout latency spikes to 2 seconds, the X-Ray trace reveals whether it's `paymentservice` (3rd-party API slow), `shippingservice` (CPU-bound calculation), or `cartservice` (Redis connection issues).

---

## Phase 5: Security Controls

### Step 13 — Kubernetes RBAC

Each microservice runs under a dedicated service account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: checkout-service
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/checkout-irsa-role
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: checkout-role
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
    resourceNames: ["checkout-config"]
```

The checkout service can only `get` its own ConfigMap — not list pods, not access secrets from other namespaces, not call the Kubernetes API beyond what it needs. Least privilege at the Kubernetes layer.

### Step 14 — Network Policies (Pod-to-Pod Isolation)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: checkout-isolation
spec:
  podSelector:
    matchLabels:
      app: checkoutservice
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 5050
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: cartservice
    - to:
        - podSelector:
            matchLabels:
              app: paymentservice
    - to:
        - podSelector:
            matchLabels:
              app: shippingservice
```

`checkoutservice` can only receive traffic from `frontend` (on port 5050) and only connect to `cartservice`, `paymentservice`, and `shippingservice`. If `adservice` (which serves contextual ads and is the highest-risk service for external data injection) is compromised, it cannot call `checkoutservice` — the NetworkPolicy blocks it.

**Why NetworkPolicies when security groups exist?**  
EC2 security groups control traffic between nodes (at the ENI level) — they cannot distinguish between two different pods running on the same node. NetworkPolicies operate at the pod label selector level — they enforce isolation regardless of which node pods are running on.

### Step 15 — External Secrets Operator (ESO) + Secrets Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: redis-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: redis-credentials  # creates a Kubernetes Secret
  data:
    - secretKey: password
      remoteRef:
        key: /nexashop/redis/password
        property: password
```

ESO fetches the secret from AWS Secrets Manager every hour and syncs it to a Kubernetes Secret. The application mounts the Kubernetes Secret as an environment variable.

**Why ESO over native Kubernetes Secrets?**

Native Kubernetes Secrets are base64-encoded — not encrypted. By default, they are stored unencrypted in etcd. Anyone with etcd read access (or a backup) can decode all secrets. While EKS can be configured to encrypt etcd with KMS, the baseline is not secure.

Secrets Manager + ESO provides:
- Secrets stored in AWS KMS-encrypted Secrets Manager (encrypted at rest and in transit)
- Automatic rotation: Secrets Manager rotates the Redis password; ESO picks up the new value within 1 hour
- CloudTrail audit log for every secret access
- Zero secrets in Git, zero secrets in container images, zero secrets in Kubernetes manifest files

---

## AWS Well-Architected Framework Analysis

### Operational Excellence

- **GitOps (ArgoCD):** Every deployment is a Git operation. The entire cluster state can be reconstructed from Git history. Operators can see exactly what version of every service is running — no "what's deployed in prod?" ambiguity
- **Rollback = `git revert`:** No special kubectl commands, no runbook entries — rollback is the same operation as any other change
- **Parallel CI builds:** Full pipeline in < 10 minutes for all 11 services running in parallel
- **Drift detection:** ArgoCD continuously monitors cluster state vs. Git. Unauthorized changes are reverted automatically

### Security

- **Trivy blocks CRITICAL CVEs before ECR push:** Zero known-critical vulnerabilities in production
- **IRSA + minimum RBAC:** Each service has exactly the AWS and Kubernetes permissions it needs — no more
- **NetworkPolicies:** Compromised service cannot reach other services beyond its declared dependencies
- **ESO + Secrets Manager:** Zero secrets in Git, manifests, or container images
- **IMDSv2 on EKS nodes:** EC2 metadata service requires a TTL-bounded token — SSRF attacks cannot steal node credentials
- **Trivy ECR scan on push:** Secondary scan after image reaches ECR — defense in depth

### Reliability

- **3-AZ deployment:** EKS nodes span 3 AZs — single AZ failure reduces capacity to 2/3, does not cause an outage
- **NAT Gateway per AZ:** Egress from any AZ works independently — no cross-AZ NAT dependency
- **Karpenter fast provisioning:** New nodes in < 60 seconds — traffic spikes are absorbed quickly
- **Pod disruption budgets:** During Karpenter consolidation, PodDisruptionBudgets ensure minimum pod count is maintained while nodes are drained
- **ArgoCD health checks:** ArgoCD monitors Deployment rollout health — a failed rollout is flagged immediately

### Performance Efficiency

- **Karpenter dynamic instance selection:** Right-sized nodes for actual workload — no over-provisioned static node groups
- **Spot instances for stateless services:** 60–90% cost reduction for frontend, catalog, recommendation services
- **Arm64 (Graviton2) nodes where available:** 20% better price-performance than x86
- **Prometheus local scraping:** No external metrics API calls — metrics collection is in-cluster

### Cost Optimization

- **~30% EC2 reduction vs static node groups:** Karpenter bin-packing + Spot usage + 30-second idle node termination
- **ECR lifecycle policies:** Max 10 images per repo — $22/month ECR storage cap
- **Graviton2 nodes:** Lower per-vCPU cost across the fleet

### Sustainability

- **Karpenter node consolidation:** Underutilized nodes are terminated within 30 seconds — no idle EC2 running
- **Spot instances:** Spot capacity is AWS's otherwise-unused compute — more efficient use of existing infrastructure
- **Horizontal pod autoscaling:** Scale to zero replica counts during overnight low-traffic — Karpenter terminates empty nodes

---

## Key Architectural Insight

The core pattern this project demonstrates is **GitOps as the operating model**. Infrastructure (Terraform state in remote backend), container images (ECR, immutable tags), and Kubernetes manifests (Git `kubernetes-manifests/`) are all version-controlled and auditable. Every change is a commit:

- "What's running in prod?" → `git log kubernetes-manifests/`
- "When did this version deploy?" → `git log kubernetes-manifests/frontend/`
- "Rollback" → `git revert` — identical to any other change

This is the difference between a cluster you understand and a cluster that understands itself. The state is always in Git, and the cluster is always converging toward it.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
