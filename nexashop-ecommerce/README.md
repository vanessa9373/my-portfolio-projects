# NexaShop — Cloud-Native E-Commerce Platform

A production-grade, cloud-native e-commerce platform built on AWS. Designed for scale, resilience, and cost efficiency — serving thousands of concurrent shoppers with sub-100ms API response times and zero-downtime deployments.

---

## Architecture Overview

```
Users → CloudFront (WAF) → S3 (Frontend) + API Gateway (Backend)
                                                    ↓
                                        Cognito Auth → Lambda Functions
                                                    ↓
                                    DynamoDB (Catalog) · Aurora (Orders)
                                    ElastiCache (Sessions) · S3 (Images)
                                                    ↓
                                    SQS → Order Processor → SES (Email)
```

**AWS Services Used:**
`CloudFront` · `WAF` · `S3` · `API Gateway` · `Lambda` · `Cognito` · `DynamoDB` · `Aurora PostgreSQL` · `ElastiCache Redis` · `SQS` · `SNS` · `SES` · `ECS Fargate` · `ECR` · `VPC` · `ALB` · `CloudWatch` · `X-Ray` · `CloudTrail` · `KMS` · `Secrets Manager` · `Terraform`

---

## Project Structure

```
nexashop-ecommerce/
├── terraform/                 # Infrastructure as Code (Terraform)
│   ├── main.tf                # Root module — orchestrates all modules
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Stack outputs
│   ├── provider.tf            # AWS provider config
│   └── modules/
│       ├── vpc/               # Multi-AZ VPC with 3-tier subnets
│       ├── cdn/               # CloudFront + WAF + S3 frontend
│       ├── ecs/               # ECS Fargate for backend API
│       ├── rds/               # Aurora PostgreSQL Multi-AZ (orders DB)
│       └── cognito/           # Cognito user pool + app client
├── src/
│   ├── products/              # Lambda: product catalog (DynamoDB)
│   ├── orders/                # Lambda: order management (Aurora)
│   ├── auth/                  # Lambda: Cognito triggers
│   └── notifications/         # Lambda: SES email + SNS events
├── .github/workflows/
│   └── deploy.yml             # CI/CD: GitHub Actions → ECR → ECS
└── docs/
    └── architecture.md        # Architecture decisions and trade-offs
```

---

## Infrastructure Design

### Networking (VPC)
- `/16` VPC across **3 Availability Zones**
- **Public subnets**: ALB, NAT Gateways
- **Private subnets**: ECS tasks, Lambda ENIs
- **Isolated subnets**: Aurora, ElastiCache (no internet route)
- VPC Flow Logs → CloudWatch Logs for network audit

### Frontend (CloudFront + S3)
- React app built via GitHub Actions, deployed to S3
- CloudFront distribution with OAC (Origin Access Control)
- WAF with OWASP Top 10 managed rules + rate limiting
- Custom error pages, HTTPS enforced, HSTS headers

### API Layer (API Gateway + Lambda)
- REST API with Cognito JWT authorizer
- Lambda functions per domain: products, orders, auth, notifications
- X-Ray tracing enabled on all functions
- Lambda Powertools for structured logging + metrics

### Database Strategy
| Store | Service | Why |
|-------|---------|-----|
| Product catalog | DynamoDB | High-read, flexible schema, single-digit ms |
| Orders + users | Aurora PostgreSQL Multi-AZ | ACID, relational, auto-failover < 30s |
| Sessions + cart | ElastiCache Redis | Sub-ms reads, TTL-based expiry |
| Product images | S3 + CloudFront | Durable, globally cached |

### Order Processing (SQS + Lambda)
1. Customer places order → API Lambda writes to SQS
2. Order Processor Lambda (SQS trigger) validates + writes to Aurora
3. On success: SES confirmation email + SNS event to downstream systems
4. On failure: DLQ captures failed messages for investigation

### Security
- **Cognito**: User registration, login, JWT tokens, MFA optional
- **IAM**: Least-privilege execution roles per Lambda function
- **KMS**: Encryption at rest — DynamoDB, Aurora, S3, Secrets Manager
- **Secrets Manager**: DB credentials with 90-day auto-rotation
- **WAF**: Rate limiting, SQL injection, XSS, known bad inputs
- **VPC**: Private subnets, no direct DB internet exposure

---

## Deployment

### Prerequisites
- AWS CLI configured with sufficient IAM permissions
- Terraform >= 1.6.0
- Node.js >= 18 (for Lambda packaging)
- Docker (for ECS image builds)

### Deploy Infrastructure
```bash
cd terraform/
terraform init
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```

### Deploy Application (CI/CD)
Every push to `main` triggers the GitHub Actions pipeline:
1. Run unit tests
2. Build Lambda packages (zip)
3. Build Docker image → push to ECR
4. Deploy Lambda updates (`aws lambda update-function-code`)
5. Deploy new ECS task definition
6. Build React frontend → sync to S3 → invalidate CloudFront

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Catalog DB | DynamoDB | Product reads 10:1 over writes; DynamoDB scales to any traffic without ops overhead |
| Orders DB | Aurora PostgreSQL | Cart + checkout requires transactions; Multi-AZ auto-failover for 99.95% SLA |
| Session cache | ElastiCache Redis | Cart persistence across requests; TTL handles abandoned carts automatically |
| Auth | Cognito | Managed user pool eliminates custom auth code; JWT integrates natively with API Gateway |
| Order queue | SQS | Decouples checkout API from downstream processing; DLQ captures failures without data loss |
| Frontend hosting | S3 + CloudFront | Zero server management; global CDN for static assets; $0.023/GB vs EC2 baseline |

---

## Estimated Cost (Production)

| Component | Monthly Est. |
|-----------|-------------|
| CloudFront + WAF | $45 |
| API Gateway (1M req) | $3.50 |
| Lambda (10M invocations) | $2.00 |
| DynamoDB (on-demand) | $28 |
| Aurora PostgreSQL t3.medium Multi-AZ | $130 |
| ElastiCache Redis t3.micro | $25 |
| ECS Fargate (2 tasks) | $35 |
| S3 (50 GB storage + transfers) | $8 |
| SQS + SES | $5 |
| CloudWatch + X-Ray | $15 |
| **Total** | **~$297/month** |

*Compared to equivalent on-prem or self-managed: ~$1,800/month*

---

## Skills Demonstrated

- Multi-tier VPC design and network segmentation
- Serverless API architecture with Lambda + API Gateway
- Polyglot persistence (DynamoDB + Aurora + ElastiCache)
- Event-driven order processing with SQS + DLQ
- CDN + WAF configuration for production traffic
- CI/CD pipeline from code push to production
- Cost modeling and infrastructure right-sizing
- Security: encryption, least-privilege IAM, Cognito auth

---

*Part of the [Cloud Engineering Portfolio](https://jenellavan.com) by Vanessa Awo*
