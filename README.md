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

## Contact

| | |
|--|--|
| 🌐 **Portfolio** | [jenellavan.com](https://jenellavan.com) |
| 💼 **LinkedIn** | [linkedin.com/in/vanessajen](https://linkedin.com/in/vanessajen) |
| 📧 **Email** | [jenellaawo93@gmail.com](mailto:jenellaawo93@gmail.com) |
| 📍 **Location** | Seattle, WA · Remote-Ready · Open to Relocation |
