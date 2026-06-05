# My Portfolio Projects

Cloud infrastructure projects by **Vanessa Awo** — Solutions Architect · Solutions Engineer · Pre-Sales SE

[![AWS](https://img.shields.io/badge/AWS-FF9900?style=flat&logo=amazonaws&logoColor=white)](https://aws.amazon.com)
[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)](https://terraform.io)
[![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)](https://python.org)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)](https://github.com/features/actions)

---

## Projects

### 1. [ha-wordpress-terraform](./ha-wordpress-terraform)
**Highly Available WordPress on AWS — Terraform IaC**

Production-grade, zero-SPOF 3-tier architecture across 3 Availability Zones.

| Component | Implementation |
|-----------|---------------|
| **IaC** | Terraform — full infrastructure as code, reproducible in one command |
| **Compute** | EC2 Auto Scaling Group behind Application Load Balancer |
| **Database** | RDS MySQL Multi-AZ — synchronous replication, <2 min automatic failover |
| **CDN** | CloudFront + S3 OAC for global content delivery |
| **Security** | WAF (OWASP/SQLi rules), IMDSv2, KMS CMK encryption, SSM Session Manager |
| **Monitoring** | CloudWatch alarms on p99 latency, 5xx rate, RDS connections |

> SA angle: Well-Architected Framework across all 6 pillars  
> SE angle: Live POC demonstrating architecture trade-offs to stakeholders

---

### 2. [multi-account-landing-zone](./multi-account-landing-zone)
**Enterprise Multi-Account AWS Landing Zone**

Enterprise-grade multi-account architecture with centralized security and governance.

| Component | Implementation |
|-----------|---------------|
| **Structure** | 4 OUs (Management, Security, Infrastructure, Workloads) · 10+ accounts |
| **Governance** | 8 SCPs — DenyRootUser, RequireIMDSv2, AllowedRegionsOnly, DenyPublicS3 |
| **Networking** | Transit Gateway hub-and-spoke · Prod↔Dev network isolation |
| **Identity** | SAML 2.0 SSO via IAM Identity Center |
| **Security** | GuardDuty + Security Hub centralized across all accounts |

---

### 3. [serverless-task-api](./serverless-task-api)
**Serverless Task Management API — 90% cheaper than EC2+RDS**

Full CRUD REST API on serverless architecture with CI/CD.

| Component | Implementation |
|-----------|---------------|
| **Compute** | 5 Lambda functions on Graviton2/arm64 — 20% cheaper than x86 |
| **API** | API Gateway HTTP API — $1.00/M vs REST API $3.50/M |
| **Database** | DynamoDB PAY_PER_REQUEST + GSI for status-based queries |
| **CI/CD** | GitHub Actions with OIDC auth — no long-lived AWS keys |
| **Cost** | ~$2.32/month at 1M requests |

---

### 4. [nexashop-ecommerce](./nexashop-ecommerce)
**NexaShop — Cloud-Native E-Commerce Platform**

Production-grade serverless e-commerce platform for 10M+ users with polyglot persistence and a full CI/CD pipeline.

| Component | Implementation |
|-----------|---------------|
| **Frontend** | React → S3 + CloudFront (OAC) + WAF (OWASP Top 10 + rate limiting) |
| **API** | Lambda + API Gateway · Cognito JWT auth · X-Ray tracing |
| **Catalog DB** | DynamoDB PAY_PER_REQUEST + category GSI for browse queries |
| **Orders DB** | Aurora PostgreSQL Multi-AZ — ACID transactions, <30s failover |
| **Sessions** | ElastiCache Redis — sub-ms cart state, TTL-based expiry |
| **Order pipeline** | SQS decoupled processing + DLQ + SES confirmation email |
| **CI/CD** | GitHub Actions: Lambda zip deploy + ECS Fargate + S3 sync + CloudFront invalidation |
| **Est. cost** | ~$297/month vs ~$1,800/month on-prem equivalent |

> SA angle: Polyglot persistence — right database for each workload (DynamoDB vs Aurora vs Redis)  
> SE angle: Live architecture trade-off demo — each ADR explains why one service beats the alternative

---

### 5. [eks-online-boutique](./eks-online-boutique)
**Online Boutique — Production-Grade Microservices on AWS EKS**

Full DevOps lifecycle for 11 real microservices across Go, Python, Java, C#, and Node.js.

| Component | Implementation |
|-----------|---------------|
| **Infrastructure** | Terraform: VPC (3 AZs) · EKS 1.28 · ECR (11 repos) · IRSA roles |
| **CI/CD** | GitHub Actions (OIDC): build → Trivy CVE scan → ECR push → manifest update |
| **GitOps** | ArgoCD: auto-sync from Git, drift detection, rollback via `git revert` |
| **Observability** | Prometheus + Grafana (golden signals) · CloudWatch Container Insights · X-Ray |
| **Security** | Trivy blocks CRITICAL CVEs · RBAC · NetworkPolicies · External Secrets Operator |
| **Autoscaling** | Karpenter: node provisioning < 60s · ~30% cost reduction vs static node groups |

> Full repo: [github.com/vanessa9373/portfolio-devops-project](https://github.com/vanessa9373/portfolio-devops-project)  
> DevOps angle: every production pattern — GitOps, observability, security, cost — implemented, not just described

---

### 6. [aws-apac-forage](./aws-apac-forage)
**AWS APAC Solutions Architecture — Forage Virtual Experience**

Simulated full SA/SE engagement: discovery → diagnosis → architecture → stakeholder presentation.

| Component | Implementation |
|-----------|---------------|
| **Discovery** | Mapped current single-EC2 architecture, identified all single points of failure |
| **Architecture** | Elastic Beanstalk + RDS Multi-AZ + CloudFront (PriceClass_200 for APAC) + Route 53 |
| **Communication** | Restaurant analogy to explain Auto Scaling to non-technical client · approved first meeting |
| **Objection handling** | Reframed $70→$280/month cost as risk elimination: 3 outages × $5K = $15K/quarter risk |
| **ADRs** | Elastic Beanstalk over EKS (right-sized for client ops capability) · CloudFront PriceClass_200 |

> SE angle: Demonstrates the full pre-sales motion — discovery, design, communication, objection handling  
> Certified by AWS · Forage · September 2025

---

## Labs

19 hands-on cloud infrastructure labs covering DevOps, Kubernetes, SRE, security, and cost optimization.

| # | Lab | Focus |
|---|-----|-------|
| 01 | [cloud-migration](./labs/01-cloud-migration) | 6R strategies, workload assessment, TCO |
| 02 | [multi-cloud-architecture](./labs/02-multi-cloud-architecture) | AWS + Azure + GCP cross-cloud design |
| 03 | [terraform-modules](./labs/03-terraform-modules) | Reusable IaC module patterns |
| 04 | [iac-terraform-ansible](./labs/04-iac-terraform-ansible) | Terraform + Ansible provisioning |
| 05 | [cicd-kubernetes](./labs/05-cicd-kubernetes) | CI/CD pipelines with Kubernetes |
| 06 | [cicd-gitops](./labs/06-cicd-gitops) | GitOps workflow with GitHub Actions |
| 07 | [cicd-argocd-rollouts](./labs/07-cicd-argocd-rollouts) | ArgoCD progressive delivery |
| 08 | [kubernetes-observability](./labs/08-kubernetes-observability) | Prometheus + Grafana on K8s |
| 09 | [sre-observability-slo](./labs/09-sre-observability-slo) | SLOs, SLIs, error budgets |
| 10 | [logging-tracing-pipeline](./labs/10-logging-tracing-pipeline) | ELK Stack + distributed tracing |
| 11 | [incident-response-slo](./labs/11-incident-response-slo) | SLO-driven incident response |
| 12 | [incident-response-postmortem](./labs/12-incident-response-postmortem) | Blameless postmortem process |
| 13 | [chaos-engineering-aws](./labs/13-chaos-engineering-aws) | AWS Fault Injection Simulator |
| 14 | [chaos-engineering-litmus](./labs/14-chaos-engineering-litmus) | LitmusChaos on Kubernetes |
| 15 | [security-compliance](./labs/15-security-compliance) | IAM, SCPs, GuardDuty, Security Hub |
| 16 | [kubernetes-security](./labs/16-kubernetes-security) | RBAC, Pod Security, network policies |
| 17 | [serverless-data-pipeline](./labs/17-serverless-data-pipeline) | Lambda + S3 + DynamoDB pipeline |
| 18 | [cloud-cost-optimization](./labs/18-cloud-cost-optimization) | FinOps, right-sizing, savings plans |
| 19 | [devops-mastery-ecommerce](./labs/19-devops-mastery-ecommerce) | End-to-end DevOps on EKS |

---

## Contact

| | |
|--|--|
| 🌐 **Portfolio** | [jenellavan.com](https://jenellavan.com) |
| 💼 **LinkedIn** | [linkedin.com/in/vanessajen](https://linkedin.com/in/vanessajen) |
| 📧 **Email** | [jenellaawo93@gmail.com](mailto:jenellaawo93@gmail.com) |
| 📍 **Location** | Seattle, WA · Remote-Ready · Open to Relocation |
