# Lab 19: E-Commerce Platform — Full DevOps Lifecycle Mastery

![AWS](https://img.shields.io/badge/AWS-FF9900?style=flat&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=flat&logo=argo&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&logoColor=white)
![Istio](https://img.shields.io/badge/Istio-466BB0?style=flat&logo=istio&logoColor=white)

## Summary

A complete end-to-end DevOps project covering **14 phases** of the DevOps lifecycle — from project foundation to platform engineering. This project builds a production-grade e-commerce microservices platform with 6 services, deployed on AWS EKS with full CI/CD, GitOps, observability, security, chaos engineering, service mesh, multi-region DR, FinOps, and an internal developer platform.

## Architecture Overview

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                    AWS Cloud (Multi-Region)              │
                    │                                                          │
  Users ──► R53 ──► │  ┌─────────┐    ┌─────────────────────────────────┐     │
                    │  │  ALB /  │───►│        EKS Cluster               │     │
                    │  │ Istio   │    │  ┌─────────┐  ┌──────────────┐  │     │
                    │  │ Ingress │    │  │API GW   │  │User Service  │  │     │
                    │  └─────────┘    │  └─────────┘  └──────────────┘  │     │
                    │                 │  ┌─────────┐  ┌──────────────┐  │     │
                    │  ┌──────────┐   │  │Product  │  │Order Service │  │     │
                    │  │ArgoCD   │   │  │Service  │  └──────────────┘  │     │
                    │  │(GitOps) │   │  └─────────┘  ┌──────────────┐  │     │
                    │  └──────────┘   │  ┌─────────┐  │Notification  │  │     │
                    │                 │  │Payment  │  │Service       │  │     │
                    │  ┌──────────┐   │  │Service  │  └──────────────┘  │     │
                    │  │Prometheus│   │  └─────────┘                    │     │
                    │  │Grafana   │   └─────────────────────────────────┘     │
                    │  │Loki      │                                            │
                    │  └──────────┘   ┌─────────────────────────────────┐     │
                    │                 │  ┌──────────┐  ┌─────────────┐  │     │
                    │                 │  │Aurora    │  │ElastiCache  │  │     │
                    │                 │  │PostgreSQL│  │Redis        │  │     │
                    │                 │  └──────────┘  └─────────────┘  │     │
                    │                 │  ┌──────────┐                   │     │
                    │                 │  │RabbitMQ  │                   │     │
                    │                 │  └──────────┘                   │     │
                    │                 └─────────────────────────────────┘     │
                    └──────────────────────────────────────────────────────────┘
```

## The 14 Phases

| Phase | Title | Difficulty | Directory |
|-------|-------|-----------|-----------|
| 1 | [Project Foundation & Version Control](#phase-1-project-foundation--version-control) | Beginner | `phase-01-foundation/` |
| 2 | [Application Development (Microservices)](#phase-2-application-development) | Beginner | `phase-02-microservices/` |
| 3 | [Containerization](#phase-3-containerization) | Beginner | `phase-03-containerization/` |
| 4 | [Infrastructure as Code](#phase-4-infrastructure-as-code) | Intermediate | `phase-04-infrastructure-as-code/` |
| 5 | [CI/CD Pipelines](#phase-5-cicd-pipelines) | Intermediate | `phase-05-cicd/` |
| 6 | [Kubernetes Orchestration](#phase-6-kubernetes-orchestration) | Intermediate | `phase-06-kubernetes/` |
| 7 | [GitOps & Continuous Delivery](#phase-7-gitops--continuous-delivery) | Intermediate | `phase-07-gitops/` |
| 8 | [Observability & Monitoring](#phase-8-observability--monitoring) | Advanced | `phase-08-observability/` |
| 9 | [Security & Compliance](#phase-9-security--compliance) | Advanced | `phase-09-security/` |
| 10 | [Chaos Engineering & Resilience](#phase-10-chaos-engineering--resilience) | Advanced | `phase-10-chaos/` |
| 11 | [Service Mesh & Advanced Networking](#phase-11-service-mesh--advanced-networking) | Expert | `phase-11-service-mesh/` |
| 12 | [Multi-Region & Disaster Recovery](#phase-12-multi-region--disaster-recovery) | Expert | `phase-12-multi-region/` |
| 13 | [FinOps & Cost Optimization](#phase-13-finops--cost-optimization) | Expert | `phase-13-finops/` |
| 14 | [Platform Engineering & Developer Portal](#phase-14-platform-engineering--developer-portal) | Expert | `phase-14-platform-engineering/` |

## Tech Stack

| Category | Technologies |
|----------|-------------|
| **Languages** | Node.js, Python, FastAPI, Express |
| **Databases** | PostgreSQL (Aurora), Redis (ElastiCache), RabbitMQ |
| **Containers** | Docker, Docker Compose, multi-stage builds, Distroless |
| **IaC** | Terraform, Terraform modules, S3 remote state |
| **CI/CD** | GitHub Actions, Trivy, Semantic Release |
| **Orchestration** | Kubernetes, EKS, Helm, HPA, PDB |
| **GitOps** | ArgoCD, Kustomize, Image Updater |
| **Observability** | Prometheus, Grafana, Loki, OpenTelemetry, Jaeger |
| **Security** | OPA/Gatekeeper, Trivy, HashiCorp Vault, Falco, RBAC |
| **Chaos** | Litmus Chaos, AWS FIS, Resilience4j |
| **Service Mesh** | Istio, Envoy, mTLS, Kiali |
| **DR** | Route 53, Aurora Global, Velero, S3 CRR |
| **FinOps** | Kubecost, Karpenter, Spot Instances, Savings Plans |
| **Platform** | Backstage, Crossplane, Self-Service Templates |

## Key Results

| Metric | Value |
|--------|-------|
| Microservices | 6 |
| Deployment frequency | 20+ deploys/day |
| Pipeline time | < 8 minutes |
| Availability SLO | 99.95% |
| mTLS coverage | 100% |
| Critical CVEs | 0 |
| Cost reduction | 40% |
| RPO / RTO | < 1 min / < 5 min |
| New service setup | 5 minutes (self-service) |

---

## Phase 1: Project Foundation & Version Control

**Difficulty:** Beginner | **Directory:** `phase-01-foundation/`

Establish a production-grade monorepo with trunk-based development, conventional commits enforced via Husky/commitlint, branch protection rules, and automated changelog generation.

**Key files:**
- `.commitlintrc.js` — Conventional commit rules with service-scoped types
- `.husky/` — Pre-commit hooks for linting and commit message validation
- Branching strategy: trunk-based with short-lived feature branches

[Read the full implementation guide →](./phase-01-foundation/README.md)

---

## Phase 2: Application Development

**Difficulty:** Beginner | **Directory:** `phase-02-microservices/`

Six microservices forming a complete e-commerce platform:

| Service | Language | Database | Purpose |
|---------|----------|----------|---------|
| API Gateway | Node.js/Express | — | Routing, rate limiting, JWT validation |
| User Service | Node.js | PostgreSQL + Redis | Authentication, profiles |
| Product Service | Python/FastAPI | PostgreSQL + Redis | Catalog, search, inventory |
| Order Service | Node.js | PostgreSQL | Order lifecycle, saga pattern |
| Payment Service | Node.js | PostgreSQL | Payment processing, idempotency |
| Notification Service | Python | — | Event-driven email/SMS |

Inter-service communication via RabbitMQ with event-driven architecture.

[Read the full implementation guide →](./phase-02-microservices/README.md)

---

## Phase 3: Containerization

**Difficulty:** Beginner | **Directory:** `phase-03-containerization/`

Multi-stage Docker builds with distroless base images, non-root execution, health checks, and Docker Compose for local development with hot-reload.

**Results:** 80% smaller images, zero root containers, < 30s build times.

[Read the full implementation guide →](./phase-03-containerization/README.md)

---

## Phase 4: Infrastructure as Code

**Difficulty:** Intermediate | **Directory:** `phase-04-infrastructure-as-code/`

Terraform modules for the full AWS stack: VPC (3 AZs), EKS with Bottlerocket nodes, RDS Aurora PostgreSQL, ElastiCache Redis, IAM with least privilege. Remote state in S3 with DynamoDB locking.

**Key files:**
- `modules/vpc/` — VPC with public/private subnets, NAT Gateways, VPC endpoints
- `modules/eks/` — EKS cluster with managed node groups
- `modules/rds/` — Aurora PostgreSQL with multi-AZ
- `environments/` — Dev, staging, production configurations

[Read the full implementation guide →](./phase-04-infrastructure-as-code/README.md)

---

## Phase 5: CI/CD Pipelines

**Difficulty:** Intermediate | **Directory:** `phase-05-cicd/`

Monorepo-aware GitHub Actions with path-filtered builds, parallel test/lint/scan jobs, Trivy container scanning, semantic versioning, and environment-specific deployment gates.

**Key files:**
- `workflows/ci.yml` — CI pipeline with path filters
- `workflows/cd.yml` — CD pipeline with environment promotion
- `scripts/` — Helper scripts for versioning and release

[Read the full implementation guide →](./phase-05-cicd/README.md)

---

## Phase 6: Kubernetes Orchestration

**Difficulty:** Intermediate | **Directory:** `phase-06-kubernetes/`

Helm charts with shared templates, HPA (CPU + custom metrics), PDB, liveness/readiness/startup probes, resource tuning, and external secrets via AWS Secrets Manager.

**Key files:**
- `helm/templates/` — Shared Helm templates
- `helm/values/` — Per-environment values files

[Read the full implementation guide →](./phase-06-kubernetes/README.md)

---

## Phase 7: GitOps & Continuous Delivery

**Difficulty:** Intermediate | **Directory:** `phase-07-gitops/`

ArgoCD Application-of-Apps pattern, Kustomize overlays, ArgoCD Image Updater for automated tag updates, sync waves, and PR-based environment promotion.

**Key files:**
- `argocd/` — ArgoCD application manifests
- `kustomize/overlays/production/` — Production Kustomize overlay

[Read the full implementation guide →](./phase-07-gitops/README.md)

---

## Phase 8: Observability & Monitoring

**Difficulty:** Advanced | **Directory:** `phase-08-observability/`

Full observability stack: Prometheus for metrics + SLI/SLO rules, Grafana dashboards, Loki for log aggregation, OpenTelemetry SDK instrumentation, Jaeger for distributed tracing, Alertmanager with PagerDuty.

**Key files:**
- `prometheus/` — Recording rules and SLO alerts
- `grafana/` — Dashboard JSON definitions
- `loki/` — Log pipeline configuration

[Read the full implementation guide →](./phase-08-observability/README.md)

---

## Phase 9: Security & Compliance

**Difficulty:** Advanced | **Directory:** `phase-09-security/`

OPA/Gatekeeper admission policies, Trivy scanning in CI, HashiCorp Vault dynamic secrets, Kubernetes Network Policies for zero-trust, RBAC with least-privilege service accounts, Pod Security Standards.

**Key files:**
- `gatekeeper/` — Constraint templates and constraints
- `vault/` — Vault configuration and policies
- `network-policies/` — Per-service network policies

[Read the full implementation guide →](./phase-09-security/README.md)

---

## Phase 10: Chaos Engineering & Resilience

**Difficulty:** Advanced | **Directory:** `phase-10-chaos/`

Litmus Chaos workflows (pod kill, network latency, CPU/memory stress), AWS FIS experiments (AZ failure, RDS failover), circuit breaker patterns, monthly game days with structured hypotheses.

**Key files:**
- `litmus/` — Chaos experiment definitions
- `aws-fis/` — FIS experiment templates

[Read the full implementation guide →](./phase-10-chaos/README.md)

---

## Phase 11: Service Mesh & Advanced Networking

**Difficulty:** Expert | **Directory:** `phase-11-service-mesh/`

Istio service mesh with strict mTLS, VirtualService/DestinationRule for weighted routing, canary deployments with automated rollback, circuit breaking, rate limiting, and Kiali visualization.

**Key files:**
- `istio/` — Istio configuration (PeerAuthentication, AuthorizationPolicy)
- `canary/` — Canary release VirtualService definitions

[Read the full implementation guide →](./phase-11-service-mesh/README.md)

---

## Phase 12: Multi-Region & Disaster Recovery

**Difficulty:** Expert | **Directory:** `phase-12-multi-region/`

Active-passive multi-region (us-east-1 + eu-west-1), Route 53 failover, Aurora Global Database, Velero backups, S3 Cross-Region Replication. RPO < 1 min, RTO < 5 min validated quarterly.

**Key files:**
- `terraform/` — Multi-region Terraform configuration
- `dr-runbooks/` — Disaster recovery runbooks

[Read the full implementation guide →](./phase-12-multi-region/README.md)

---

## Phase 13: FinOps & Cost Optimization

**Difficulty:** Expert | **Directory:** `phase-13-finops/`

Kubecost for cost allocation, Karpenter with Spot instance preference, right-sizing recommendations, Compute Savings Plans, idle resource cleanup, cost anomaly alerts.

**Key files:**
- `karpenter/` — Provisioner and node pool configuration
- `kubecost/` — Cost allocation policies

**Results:** 40% cost reduction, 70% Spot utilization.

[Read the full implementation guide →](./phase-13-finops/README.md)

---

## Phase 14: Platform Engineering & Developer Portal

**Difficulty:** Expert | **Directory:** `phase-14-platform-engineering/`

Backstage developer portal with service catalog, golden path templates for new microservice scaffolding, Crossplane compositions for self-service infrastructure, API documentation aggregation, service maturity scorecards.

**Key files:**
- `backstage/templates/` — Software templates for new services
- `crossplane/` — Crossplane compositions for databases, caches, queues

**Results:** 5-minute new service setup, 100% services cataloged.

[Read the full implementation guide →](./phase-14-platform-engineering/README.md)

---

## Learning Path

Follow the phases sequentially — each builds on the previous one.

| Phase | Time Estimate | What You'll Learn |
|-------|--------------|-------------------|
| 1. Foundation | 2-3 hours | Git workflows, conventional commits, monorepo structure |
| 2. Microservices | 6-8 hours | DDD boundaries, event-driven architecture, database-per-service |
| 3. Containerization | 3-4 hours | Multi-stage builds, distroless images, non-root containers |
| 4. Infrastructure as Code | 6-8 hours | Terraform modules, VPC design, EKS, Aurora PostgreSQL |
| 5. CI/CD | 5-7 hours | GitHub Actions, path-filtered builds, Trivy scanning |
| 6. Kubernetes | 5-7 hours | Helm charts, HPA, PDB, health probes, IRSA |
| 7. GitOps | 4-5 hours | ArgoCD, Kustomize overlays, Image Updater |
| 8. Observability | 6-8 hours | Prometheus SLOs, Grafana, Loki, distributed tracing |
| 9. Security | 6-8 hours | OPA/Gatekeeper, Vault, network policies, zero-trust |
| 10. Chaos Engineering | 5-7 hours | Litmus Chaos, AWS FIS, hypothesis-driven testing |
| 11. Service Mesh | 6-8 hours | Istio mTLS, canary deployments, Flagger, circuit breaking |
| 12. Multi-Region | 8-10 hours | Route 53 failover, Aurora Global, disaster recovery |
| 13. FinOps | 5-7 hours | Karpenter, Spot instances, Kubecost, resource quotas |
| 14. Platform Engineering | 6-8 hours | Backstage templates, Crossplane, self-service infrastructure |
| **Total** | **~80 hours** | **Complete DevOps lifecycle mastery** |

---

## Project Structure

```
19-devops-mastery-ecommerce/
├── README.md
├── phase-01-foundation/
│   ├── README.md                          # Implementation guide
│   └── .commitlintrc.js
├── phase-02-microservices/
│   ├── README.md                          # Implementation guide
│   ├── docker-compose.dev.yml
│   └── services/
│       ├── api-gateway/
│       ├── user-service/
│       ├── product-service/
│       ├── order-service/
│       ├── payment-service/
│       └── notification-service/
├── phase-03-containerization/
│   ├── README.md                          # Implementation guide
│   └── Dockerfile
├── phase-04-infrastructure-as-code/
│   ├── README.md                          # Implementation guide
│   ├── modules/
│   │   ├── vpc/main.tf
│   │   ├── eks/main.tf
│   │   └── rds/main.tf
│   └── environments/
│       └── production.tfvars
├── phase-05-cicd/
│   ├── README.md                          # Implementation guide
│   ├── workflows/
│   │   ├── ci.yml
│   │   └── cd.yml
│   └── scripts/
│       ├── version-bump.sh
│       └── release.sh
├── phase-06-kubernetes/
│   ├── README.md                          # Implementation guide
│   └── helm/
│       ├── Chart.yaml
│       ├── templates/
│       └── values/production.yaml
├── phase-07-gitops/
│   ├── README.md                          # Implementation guide
│   ├── argocd/application.yaml
│   └── kustomize/
│       ├── base/kustomization.yaml
│       └── overlays/production/kustomization.yaml
├── phase-08-observability/
│   ├── README.md                          # Implementation guide
│   ├── prometheus/slo-rules.yml
│   ├── grafana/dashboards/slo-overview.json
│   └── loki/loki-config.yaml
├── phase-09-security/
│   ├── README.md                          # Implementation guide
│   ├── gatekeeper/require-nonroot.yaml
│   ├── vault/
│   │   ├── vault-config.hcl
│   │   └── policies/ecommerce-app.hcl
│   └── network-policies/user-service.yaml
├── phase-10-chaos/
│   ├── README.md                          # Implementation guide
│   ├── litmus/pod-kill.yaml
│   └── aws-fis/az-failure-experiment.json
├── phase-11-service-mesh/
│   ├── README.md                          # Implementation guide
│   ├── istio/peer-authentication.yaml
│   └── canary/canary-release.yaml
├── phase-12-multi-region/
│   ├── README.md                          # Implementation guide
│   ├── terraform/route53.tf
│   └── dr-runbooks/failover-runbook.md
├── phase-13-finops/
│   ├── README.md                          # Implementation guide
│   ├── karpenter/provisioner.yaml
│   └── kubecost/cost-allocation.yaml
└── phase-14-platform-engineering/
    ├── README.md                          # Implementation guide
    ├── backstage/templates/new-microservice.yaml
    └── crossplane/database-composition.yaml
```

---

## How to Use This Project

Each phase has a detailed implementation guide (README.md) with step-by-step instructions, configuration walkthroughs, verification checklists, and troubleshooting guides.

```bash
# Clone the repository
git clone https://github.com/vanessa9373/portfolio.git
cd portfolio/labs/19-devops-mastery-ecommerce

# Start with Phase 1 — read the implementation guide
cat phase-01-foundation/README.md

# Each phase builds on the previous one
# Follow them sequentially for the best learning experience

# Quick start: run the microservices locally (Phase 2-3)
cd phase-02-microservices
docker compose -f docker-compose.dev.yml up -d
curl http://localhost:3000/health

# Provision AWS infrastructure (Phase 4)
cd ../phase-04-infrastructure-as-code/environments
terraform init && terraform plan -var-file=production.tfvars

# Explore any phase's configuration files
ls phase-08-observability/prometheus/     # SLO rules
ls phase-09-security/gatekeeper/          # Admission policies
ls phase-12-multi-region/dr-runbooks/     # Failover runbook (670 lines)
```

## Role

**DevOps Engineer & Platform Architect** — Designed and implemented the entire DevOps lifecycle for the e-commerce platform, from initial project scaffolding to a self-service internal developer platform.
