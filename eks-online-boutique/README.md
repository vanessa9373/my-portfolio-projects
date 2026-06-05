# Online Boutique — Production-Grade Microservices on AWS EKS

> **Engineer:** Vanessa Awo · AWS Solutions Architect Associate  
> **Stack:** EKS · Terraform · ArgoCD · GitHub Actions · Prometheus · Grafana · Karpenter · Trivy  
> **Status:** Production-deployed ✅ | GitOps ✅ | Observability ✅ | Security Scanning ✅  
> **Full repo:** [github.com/vanessa9373/portfolio-devops-project](https://github.com/vanessa9373/portfolio-devops-project)

---

## Problem Statement

Deploy a real 11-service microservices e-commerce application (Google's Online Boutique) on AWS EKS with production-grade CI/CD, GitOps continuous deployment, full observability, container security scanning, and cost-efficient node autoscaling — end to end, no shortcuts, no toy examples.

**Goal:** Demonstrate the complete DevOps engineering lifecycle: infrastructure as code, containerized CI/CD, declarative GitOps, metrics and alerting platform, security scanning in the pipeline, and intelligent node autoscaling.

---

## Architecture

```
Internet
    │
[Route 53] ──► DNS resolution
    │
[ACM Certificate] ──► TLS termination
    │
[Application Load Balancer] ──► HTTPS ingress
    │
[VPC — 3 Availability Zones]
    ├── Public Subnets   ──► NAT Gateways, ALB nodes
    └── Private Subnets  ──► EKS Worker Nodes (Karpenter-managed)
              │
              ├── frontend              (Go)       ──► serves the storefront UI
              ├── cartservice           (C#)        ──► ElastiCache Redis
              ├── checkoutservice       (Go)        ──► orchestrates purchase flow
              ├── paymentservice        (Node.js)   ──► processes payments
              ├── productcatalogservice (Go)        ──► product listings
              ├── currencyservice       (Node.js)   ──► currency conversion
              ├── shippingservice       (Go)        ──► shipping cost calculation
              ├── emailservice          (Python)    ──► sends order confirmations
              ├── recommendationservice (Python)    ──► product recommendations
              ├── adservice             (Java)      ──► contextual ad serving
              └── loadgenerator         (Python)    ──► Locust traffic simulation

Supporting Infrastructure:
├── ECR              ──► Container registry (11 repositories, one per service)
├── GitHub Actions   ──► CI pipeline: build → Trivy scan → push → manifest update
├── ArgoCD           ──► GitOps operator: auto-sync cluster state from Git
├── Prometheus       ──► Metrics collection (Kubernetes + application metrics)
├── Grafana          ──► Dashboards, latency p50/p95/p99, error rates, alerts
├── CloudWatch       ──► AWS-native Container Insights + log aggregation
├── Karpenter        ──► Node autoscaling (<60s provisioning, spot+on-demand)
└── Secrets Manager  ──► Secure secrets (External Secrets Operator syncs to K8s)
```

---

## What I Built

### Infrastructure (Terraform)

| Module | What It Provisions |
|--------|-------------------|
| `modules/vpc/` | VPC 10.0.0.0/16 · 3 public + 3 private subnets across 3 AZs · NAT GW per AZ · VPC Flow Logs |
| `modules/eks/` | EKS 1.28 cluster · Managed node groups · OIDC provider for IRSA |
| `modules/ecr/` | 11 ECR repositories · Lifecycle policies (keep last 10 images) · Scan on push |
| `modules/iam/` | IRSA roles for: Load Balancer Controller · Karpenter · Cluster Autoscaler · ExternalDNS |

### CI/CD Pipeline (GitHub Actions)

```
Push to main
    │
    ├── [parallel] Build Docker image per changed service
    ├── [parallel] Trivy vulnerability scan — CRITICAL = block deploy
    ├── [parallel] Push to ECR with Git SHA tag
    │
    └── Update kubernetes-manifests/ with new image tags
            │
            └── Push manifest commit to Git
                    │
                    └── ArgoCD detects diff → auto-syncs cluster
```

- OIDC authentication — no long-lived AWS keys stored in GitHub Secrets
- Independent service builds run in parallel — full pipeline in under 10 minutes
- Trivy scans block deployment of images with CRITICAL CVEs before they reach ECR

### GitOps (ArgoCD)

- ArgoCD Application CRDs declare desired state per service
- Any `git push` to `kubernetes-manifests/` automatically syncs to EKS cluster
- Rollback = `git revert` — no special commands
- Drift detection: ArgoCD alerts if live cluster diverges from Git
- ArgoCD UI shows sync status, health, and resource graph per service

### Observability (Prometheus + Grafana + CloudWatch)

| Signal | Tooling | Key Metrics |
|--------|---------|------------|
| Application metrics | Prometheus scrape | Request rate · Latency p50/p95/p99 · Error rate per service |
| Kubernetes metrics | kube-state-metrics | Pod restarts · Pending pods · Node pressure |
| Node metrics | Node Exporter | CPU · Memory · Disk I/O per node |
| Container logs | CloudWatch Container Insights | Structured logs from all 11 services |
| Distributed traces | AWS X-Ray | Service-to-service call chains, latency attribution |
| Alert rules | Prometheus AlertManager | PodCrashLooping · HighLatency · NodeCPU > 80% |

Grafana dashboards: cluster overview, per-service golden signals, Karpenter node activity.

### Security

| Control | Implementation |
|---------|---------------|
| Container scanning | Trivy in CI — CRITICAL CVEs block ECR push |
| Kubernetes RBAC | ClusterRole/RoleBinding per service account — minimum permissions |
| Network isolation | NetworkPolicy manifests — each service allows only required ingress/egress |
| Secrets | AWS Secrets Manager + External Secrets Operator — zero secrets in Git or manifests |
| Node security | IMDSv2 enforced on EKS nodes · Private subnets only (no public node IPs) |
| Image policy | ECR scan on push · Only tagged images from CI pipeline accepted |

### Karpenter — Node Autoscaling

- Replaces Cluster Autoscaler for intelligent, fast node provisioning
- Provisions the right instance type for each workload (spot for dev, on-demand for prod)
- New nodes ready in **under 60 seconds** (vs 3–5 minutes for Cluster Autoscaler)
- Automatic node consolidation — underutilized nodes terminated, workloads bin-packed
- **~30% EC2 cost reduction** vs pre-sized static node groups

---

## Architecture Decision Records (ADRs)

### ADR-001: ArgoCD over Flux (GitOps Operator)
**Context:** Choosing a GitOps operator to sync Kubernetes manifests from Git.  
**Decision:** ArgoCD.  
**Reason:** ArgoCD has a UI for visualizing sync status, app health, and resource graphs — critical for demos, troubleshooting, and explaining GitOps to non-Kubernetes audiences. Flux is CLI-first with no built-in UI.  
**Trade-off:** ArgoCD is heavier (more cluster resources). Acceptable for a portfolio project; Flux preferred in resource-constrained environments.

### ADR-002: Karpenter over Cluster Autoscaler
**Context:** EKS node autoscaling.  
**Decision:** Karpenter.  
**Reason:** Karpenter provisions nodes in < 60s and selects optimal instance types per workload constraints. Cluster Autoscaler is tied to pre-defined node groups and scales in 3–5 minutes. Karpenter also consolidates underutilized nodes automatically, reducing idle EC2 spend.  
**Cost accepted:** Karpenter requires an additional IAM role and SQS queue for interruption handling.

### ADR-003: External Secrets Operator over Kubernetes Secrets
**Context:** Storing application credentials in Kubernetes.  
**Decision:** AWS Secrets Manager + External Secrets Operator.  
**Reason:** Native Kubernetes Secrets are base64-encoded — not encrypted at rest by default without additional KMS configuration. ESO fetches from Secrets Manager at runtime; rotation is automatic and audited in CloudTrail. Zero secrets stored in Git or manifests.  
**Trade-off:** Adds ESO as a cluster dependency. Justified by security posture.

### ADR-004: Trivy Scanning in CI (Not Runtime)
**Context:** Container vulnerability scanning.  
**Decision:** Trivy in GitHub Actions CI, blocking deploys on CRITICAL CVEs.  
**Reason:** Fail fast — catching vulnerabilities before ECR push is cheaper and faster than detecting them after deployment. Runtime scanning adds overhead to running containers. CI scanning is the first, cheapest line of defense.  
**Trade-off:** New CVEs discovered after deploy won't be blocked by this gate. Supplement with Falco or ECR scan on push for runtime coverage.

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Services deployed | 11 microservices (Go · Python · Java · C# · Node.js) |
| CI pipeline duration | < 10 minutes (parallel service builds) |
| Node provisioning | < 60 seconds (Karpenter) |
| EC2 cost reduction | ~30% vs static node groups |
| Security gate | CRITICAL CVEs block deploy |
| Rollback mechanism | `git revert` → ArgoCD auto-sync |
| Log retention | CloudWatch: 30 days |

---

## Deploy

```bash
# Prerequisites: kubectl, helm, terraform >= 1.6, AWS CLI, argocd CLI

# 1. Provision infrastructure
cd terraform/
terraform init
terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name online-boutique --region us-east-1

# 3. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. Apply ArgoCD Application definitions
kubectl apply -f argocd/

# 5. ArgoCD will sync all 11 services automatically
argocd app list

# 6. Install Prometheus + Grafana
helm upgrade --install monitoring helm-charts/monitoring/ -n monitoring --create-namespace

# 7. Access Grafana
kubectl port-forward svc/grafana 3000:80 -n monitoring
# Open http://localhost:3000
```

---

## Project Structure

```
eks-online-boutique/ (portfolio-devops-project repo)
├── terraform/
│   ├── modules/vpc/         # VPC, 3 AZs, NAT GWs, Flow Logs
│   ├── modules/eks/         # EKS cluster, node groups, OIDC
│   ├── modules/ecr/         # 11 ECR repos, lifecycle policies
│   └── modules/iam/         # IRSA roles (LBC, Karpenter, DNS)
├── kubernetes-manifests/    # Deployment + Service YAML per service
├── argocd/                  # Application CRDs, AppProject
├── helm-charts/monitoring/  # Prometheus stack, Grafana dashboards
├── monitoring/alerts/       # Prometheus AlertManager rules
├── security/                # RBAC, NetworkPolicies
├── scripts/                 # Setup, teardown, health-check
└── .github/workflows/       # Build → Trivy → ECR → manifest update
```

---

## Skills Demonstrated

- **Kubernetes on AWS:** EKS cluster provisioning, managed node groups, IRSA, OIDC
- **Infrastructure as Code:** Terraform modules for VPC, EKS, ECR, IAM — reproducible from one command
- **CI/CD:** GitHub Actions with OIDC, parallel service builds, Trivy security gate
- **GitOps:** ArgoCD declarative deployments, drift detection, Git-as-single-source-of-truth
- **Observability:** Prometheus + Grafana (golden signals), CloudWatch Container Insights, X-Ray tracing
- **Security:** Trivy CVE scanning, Kubernetes RBAC, NetworkPolicies, ESO + Secrets Manager
- **Cost optimization:** Karpenter intelligent node scaling, spot instance usage, node consolidation
- **Multi-language microservices:** Operating Go, Python, Java, C#, and Node.js services in one cluster

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
