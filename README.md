<div align="center">

# Vanessa Awo — AWS Solutions Architect Portfolio

**Solutions Architect · Solutions Engineer · Pre-Sales SE**

[![Portfolio](https://img.shields.io/badge/Portfolio-jenellavan.com-00b4d8?style=flat&logo=githubpages&logoColor=white)](https://jenellavan.com)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-vanessajen-0A66C2?style=flat&logo=linkedin&logoColor=white)](https://linkedin.com/in/vanessajen)
[![AWS SAA-C03](https://img.shields.io/badge/AWS_SAA--C03-Certified-FF9900?style=flat&logo=amazonaws&logoColor=white)](https://jenellavan.com)
[![AWS CCP](https://img.shields.io/badge/AWS_CCP-Certified-FF9900?style=flat&logo=amazonaws&logoColor=white)](https://jenellavan.com)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=flat&logo=terraform&logoColor=white)](https://terraform.io)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI/CD-2088FF?style=flat&logo=githubactions&logoColor=white)](https://github.com/features/actions)

</div>

---

## What's In This Repo

6 production-grade AWS cloud projects built to demonstrate the full Solutions Architect skill set — infrastructure design, Terraform IaC, Well-Architected trade-off analysis, and stakeholder-facing documentation.

Every project includes:
- **Terraform IaC** — reproducible, reviewable infrastructure
- **Architecture diagrams** — Draw.io with AWS icons, visual on [jenellavan.com/architecture](https://jenellavan.com/architecture.html)
- **Well-Architected docs** — design decisions with explicit trade-offs
- **SA/SE framing** — how I'd present each project in a discovery call or technical demo

---

## Projects at a Glance

| # | Project | Key Services | Highlights |
|---|---------|-------------|------------|
| 1 | [HA WordPress](#1-ha-wordpress-on-aws) | EC2 ASG · RDS Multi-AZ · CloudFront · WAF | Zero-SPOF · 3 AZs · Full IaC |
| 2 | [Multi-Account Landing Zone](#2-multi-account-aws-landing-zone) | AWS Organizations · SCPs · Transit Gateway · IAM Identity Center | 8 SCPs · 10+ accounts · SAML SSO |
| 3 | [Serverless Task API](#3-serverless-task-api) | Lambda · API Gateway · DynamoDB · Cognito | 90% cheaper than EC2+RDS · ~$2.32/mo |
| 4 | [NexaShop E-Commerce](#4-nexashop-e-commerce-platform) | Lambda · Aurora · DynamoDB · ElastiCache · SQS | Polyglot persistence · 10M+ users |
| 5 | [EKS Online Boutique](#5-eks-microservices-platform) | EKS · ArgoCD · Prometheus · Karpenter · Trivy | GitOps · 11 microservices · 5 languages |
| 6 | [AWS APAC Forage SA](#6-aws-apac-solutions-architecture-simulation) | Elastic Beanstalk · RDS · CloudFront · Route 53 | Full pre-sales motion · Forage certified |



**Plus:** [19 hands-on labs](#labs) — Kubernetes, GitOps, chaos engineering, SRE, FinOps, security

---

## Project Details

### 1. HA WordPress on AWS

> `./ha-wordpress-terraform`

Production-grade, zero-SPOF 3-tier architecture across 3 Availability Zones — designed around the AWS Well-Architected Framework.

| Component | Implementation |
|-----------|---------------|
| **IaC** | Terraform — full infrastructure as code, reproducible in one command |
| **Compute** | EC2 Auto Scaling Group behind Application Load Balancer |
| **Database** | RDS MySQL Multi-AZ — synchronous replication, <2 min automatic failover |
| **CDN** | CloudFront + S3 OAC for global content delivery |
| **Security** | WAF (OWASP/SQLi rules), IMDSv2, KMS CMK encryption, SSM Session Manager |
| **Monitoring** | CloudWatch alarms on p99 latency, 5xx rate, RDS connections |

**SA angle:** Well-Architected review across all 6 pillars with explicit trade-off docs  
**SE angle:** Live POC demonstrating failover behavior to a non-technical stakeholder

---

### 2. Multi-Account AWS Landing Zone

> `./multi-account-landing-zone`

Enterprise-grade multi-account governance — the foundational architecture every large customer needs before scaling workloads on AWS.

| Component | Implementation |
|-----------|---------------|
| **Structure** | 4 OUs (Management, Security, Infrastructure, Workloads) · 10+ accounts |
| **Governance** | 8 SCPs — DenyRootUser, RequireIMDSv2, AllowedRegionsOnly, DenyPublicS3 |
| **Networking** | Transit Gateway hub-and-spoke · Prod↔Dev network isolation |
| **Identity** | SAML 2.0 SSO via IAM Identity Center |
| **Security** | GuardDuty + Security Hub centralized across all member accounts |

**SA angle:** Governance-first design — built for a team scaling from 1 to 50+ accounts  
**Blog post:** [How I Built a Multi-Account AWS Landing Zone from Scratch](https://jenellavan.com/posts/multi-account-landing-zone.html)

---

### 3. Serverless Task API

> `./serverless-task-api`

Full CRUD REST API on serverless architecture with CI/CD — 90% cost reduction vs equivalent EC2+RDS.

| Component | Implementation |
|-----------|---------------|
| **Compute** | 5 Lambda functions on Graviton2/arm64 — 20% cheaper than x86 |
| **API** | API Gateway HTTP API — $1.00/M requests vs REST API $3.50/M |
| **Database** | DynamoDB PAY_PER_REQUEST + GSI for status-based queries |
| **Auth** | Cognito User Pools — JWT validation on every endpoint |
| **CI/CD** | GitHub Actions with OIDC auth — no long-lived AWS keys |
| **Est. cost** | ~$2.32/month at 1M requests/month |

**SA angle:** Cost model comparison vs EC2+RDS — quantified TCO for the architecture decision  
**SE angle:** 30-minute live demo that shows serverless trade-offs with real numbers

---

### 4. NexaShop E-Commerce Platform

> `./nexashop-ecommerce`

Cloud-native e-commerce platform designed for 10M+ users — polyglot persistence, decoupled order processing, full CI/CD.

| Component | Implementation |
|-----------|---------------|
| **Frontend** | React → S3 + CloudFront (OAC) + WAF (OWASP Top 10 + rate limiting) |
| **API** | Lambda + API Gateway · Cognito JWT auth · X-Ray tracing |
| **Catalog DB** | DynamoDB PAY_PER_REQUEST + category GSI for browse queries |
| **Orders DB** | Aurora PostgreSQL Multi-AZ — ACID transactions, <30s failover |
| **Sessions** | ElastiCache Redis — sub-millisecond cart reads, TTL-based expiry |
| **Order pipeline** | SQS decoupled processing + DLQ + SES confirmation email |
| **CI/CD** | GitHub Actions: Lambda zip → ECS Fargate → S3 sync → CloudFront invalidation |
| **Est. cost** | ~$297/month vs ~$1,800/month on-prem equivalent |

**SA angle:** Polyglot persistence — right database for each workload with explicit ADRs  
**SE angle:** Architecture decision records (ADRs) explain every choice vs the alternative

---

### 5. EKS Microservices Platform

> `./eks-online-boutique`  
> Full repo: [vanessa9373/portfolio-devops-project](https://github.com/vanessa9373/portfolio-devops-project)

Full DevOps lifecycle for 11 real microservices across Go, Python, Java, C#, and Node.js — every production pattern implemented.

| Component | Implementation |
|-----------|---------------|
| **Infrastructure** | Terraform: VPC (3 AZs) · EKS 1.28 · ECR (11 repos) · IRSA roles |
| **CI/CD** | GitHub Actions (OIDC): build → Trivy CVE scan → ECR push → manifest update |
| **GitOps** | ArgoCD: auto-sync from Git, drift detection, rollback via `git revert` |
| **Observability** | Prometheus + Grafana (golden signals) · CloudWatch Container Insights · X-Ray |
| **Security** | Trivy blocks CRITICAL CVEs · RBAC · NetworkPolicies · External Secrets Operator |
| **Autoscaling** | Karpenter: node provisioning <60s · ~30% cost reduction vs static node groups |

---

### 6. AWS APAC Solutions Architecture Simulation

> `./aws-apac-forage`

Simulated full SA/SE engagement — from technical discovery to architecture design to stakeholder presentation. Certified by AWS × Forage.

| Component | Implementation |
|-----------|---------------|
| **Discovery** | Mapped single-EC2 architecture, identified all single points of failure |
| **Architecture** | Elastic Beanstalk + RDS Multi-AZ + CloudFront (PriceClass_200) + Route 53 |
| **Communication** | Restaurant analogy to explain Auto Scaling to a non-technical client |
| **Objection handling** | Reframed $70→$280/month cost as risk elimination: 3 outages × $5K = $15K/quarter risk |
| **ADRs** | Elastic Beanstalk over EKS (right-sized for client ops capability) |

**SE angle:** Demonstrates the complete pre-sales motion — discovery → design → communication → objection handling

---

## Labs

19 hands-on cloud infrastructure labs covering Kubernetes, GitOps, chaos engineering, SRE, security, and FinOps.

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
| Live Portfolio | [jenellavan.com](https://jenellavan.com) |
| Architecture Diagrams | [jenellavan.com/architecture.html](https://jenellavan.com/architecture.html) |
| LinkedIn | [linkedin.com/in/vanessajen](https://linkedin.com/in/vanessajen) |
| Email | [jenellaawo93@gmail.com](mailto:jenellaawo93@gmail.com) |
| Location | Seattle, WA · Remote-Ready · Open to Relocation |
