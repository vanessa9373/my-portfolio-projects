# Highly Available WordPress on AWS — Terraform

> **Architect:** Vanessa Awo · AWS Solutions Architect Associate  
> **Stack:** Terraform · AWS EC2 · RDS Multi-AZ · ALB · CloudFront · WAF · S3  
> **Status:** Production-deployed ✅ | Infrastructure-as-Code ✅ | Zero SPOF ✅

---

## Problem Statement

A client running WordPress on a single EC2 instance experienced **3 outages in Q4** (45–90 min each), costing an estimated **$8,000 in lost revenue** per outage. The site handled ~500 concurrent users at peak and had no automated backups, no SSL, and no CDN.

**Goal:** Design and deploy an architecture that achieves **99.9% availability SLO** with auto-scaling, automated failover, and global content delivery — while reducing monthly infrastructure cost by 20%.

---

## Architecture

```
                         ┌─────────────────────────────────────────────────────────┐
                         │                   AWS Cloud (us-east-1)                  │
Internet Users           │                                                           │
     │                   │  ┌──────────────────────────────────────────────────┐    │
     ▼                   │  │                  VPC 10.0.0.0/16                  │    │
  Route 53               │  │                                                   │    │
  (DNS + Health)         │  │  AZ-1a              AZ-1b              AZ-1c      │    │
     │                   │  │  ┌──────────┐       ┌──────────┐       ┌──────┐   │    │
     ▼                   │  │  │  Public  │       │  Public  │       │Public│   │    │
  CloudFront ◄──WAF      │  │  │10.0.1/24 │       │10.0.2/24 │       │10.0.3│   │    │
  (CDN + TLS)            │  │  └─────┬────┘       └────┬─────┘       └──┬───┘   │    │
     │         ┌─────────┤  │        │ALB node          │ALB node        │ALB    │    │
     │         │ S3 Media│  │        └──────────────────┴────────────────┘       │    │
     │         │ Bucket  │  │                         │                           │    │
     │         └─────────┤  │              ┌──────────▼──────────┐               │    │
     │                   │  │              │  Application LB      │               │    │
     ▼                   │  │              │  (HTTPS 443 only)    │               │    │
  ┌─────────┐            │  │              └──────────┬──────────┘               │    │
  │ ALB     │            │  │                         │                           │    │
  │ (HA)    │            │  │  ┌──────────┐       ┌───┴──────┐       ┌──────┐   │    │
  └─────────┘            │  │  │ Private  │       │ Private  │       │Priv. │   │    │
                         │  │  │10.0.11/24│       │10.0.12/24│       │10.13 │   │    │
                         │  │  │ EC2 (WP) │       │ EC2 (WP) │       │EC2   │   │    │
                         │  │  │ ASG min2 │       │ max10    │       │      │   │    │
                         │  │  └────┬─────┘       └────┬─────┘       └──┬───┘   │    │
                         │  │       │NAT GW             │NAT GW          │NAT    │    │
                         │  │  ┌────▼─────┐       ┌────▼─────┐       ┌──▼───┐   │    │
                         │  │  │  Data    │       │  Data    │       │Data  │   │    │
                         │  │  │10.0.21/24│       │10.0.22/24│       │10.23 │   │    │
                         │  │  │  RDS     │       │  RDS     │       │(sync)│   │    │
                         │  │  │ Primary  │◄─────►│ Standby  │       │      │   │    │
                         │  │  └──────────┘sync   └──────────┘       └──────┘   │    │
                         │  │                                                   │    │
                         │  └──────────────────────────────────────────────────┘    │
                         │                                                           │
                         │  CloudTrail · AWS Config · CloudWatch · AWS Backup       │
                         └─────────────────────────────────────────────────────────┘
```

---

## What I Built

| Layer | Technology | Design Decision |
|-------|-----------|-----------------|
| **DNS** | Route 53 (Alias) | Points to CloudFront, not ALB directly — hides origin |
| **CDN** | CloudFront (PriceClass_100) | Static assets cached at edge; dynamic PHP bypassed |
| **WAF** | WAF WebACL | OWASP ruleset + SQLi + rate limiting (2000 req/5min) |
| **Network** | 3-tier VPC, 3 AZs | Public (ALB) → Private (EC2) → Data (RDS) — no SPOF |
| **NAT** | 1 NAT GW per AZ | Independent egress per AZ — single NAT = SPOF |
| **Compute** | EC2 ASG t3.medium | Target tracking: 70% CPU → scale in/out |
| **Load Balancer** | ALB HTTPS 443 | HTTP→HTTPS redirect, TLS 1.3, access logs to S3 |
| **Database** | RDS MySQL 8.0 Multi-AZ | Synchronous replication, <2 min automatic failover |
| **Storage** | gp3 EBS + S3 + lifecycle | gp3 = 20% cheaper than gp2, same IOPS |
| **Encryption** | KMS CMK | EBS volumes, RDS, S3, Secrets Manager all encrypted |
| **Secrets** | Secrets Manager | DB password auto-rotated, fetched via VPC endpoint |
| **Monitoring** | CloudWatch + SNS | 5xx alarm, latency p99 alarm, RDS CPU/storage alarms |
| **Backup** | AWS Backup | Daily 30-day retention, weekly 90-day retention |
| **IaC** | Terraform modules | Modular: vpc, compute, database, cdn, security, monitoring |

---

## Architecture Decision Records (ADRs)

### ADR-001: EC2 ASG over ECS Fargate
**Context:** Need to run WordPress PHP across multiple instances with shared state via S3.  
**Decision:** EC2 Auto Scaling Group with Launch Templates.  
**Reason:** WordPress plugins have native EC2/cPanel assumptions; ECS adds container complexity for no benefit at this scale.  
**Trade-off accepted:** Manual AMI patching vs. managed containers.

### ADR-002: One NAT Gateway per AZ (not shared)
**Context:** Three private subnets across 3 AZs need internet egress for package updates.  
**Decision:** Deploy one NAT GW in each public subnet.  
**Reason:** A single NAT GW in one AZ = SPOF. If AZ-1a fails, NAT GW fails, ALL instances lose internet even if they're healthy in AZ-1b/1c.  
**Cost accepted:** ~$96/month vs. ~$32/month. 99.9% SLO requires this.

### ADR-003: CloudFront in front of ALB (not direct ALB)
**Context:** WordPress serves static media globally; ALB is regional.  
**Decision:** CloudFront with ALB as origin, WAF on CloudFront.  
**Reason:** 40–60% reduction in ALB request count (media served from cache), WAF at edge blocks attacks before they reach origin.  
**Trade-off:** Cache invalidation complexity on WordPress updates (handled via CloudFront invalidation on deploy).

### ADR-004: RDS gp3 over gp2
**Context:** Database storage for 50 GB initial, expected to grow.  
**Decision:** gp3 storage type.  
**Reason:** gp3 is 20% cheaper than gp2 AND allows independent IOPS/throughput scaling. gp2 IOPS are tied to storage size (3 IOPS/GB = 150 IOPS at 50 GB). gp3 gives 3000 IOPS baseline at any size.

### ADR-005: Secrets Manager over SSM Parameter Store (SecureString)
**Context:** Need to store RDS credentials securely, accessible from EC2 user-data.  
**Decision:** Secrets Manager with automatic rotation.  
**Reason:** Secrets Manager supports automatic rotation via Lambda — no manual secret updates when rotating DB passwords. SSM SecureString requires custom rotation logic.  
**Cost accepted:** ~$0.40/secret/month vs. $0 for SSM.

---

## Cost Breakdown

| Resource | Spec | Monthly Cost (USD) |
|----------|------|-------------------|
| EC2 ASG | 2× t3.medium (avg), on-demand | ~$60 |
| ALB | 1 ALB, ~500k requests/day | ~$25 |
| NAT Gateways | 3× (one per AZ) | ~$100 |
| RDS MySQL | db.t3.medium Multi-AZ | ~$100 |
| CloudFront | PriceClass_100, ~1 TB/month | ~$85 |
| S3 | Media bucket + logs | ~$10 |
| WAF | ~1M requests/month | ~$10 |
| CloudWatch | Metrics + dashboards + logs | ~$15 |
| Secrets Manager | 2 secrets | ~$1 |
| AWS Backup | 30-day retention | ~$5 |
| Data Transfer | ALB → CloudFront | ~$0 (same region) |
| **Total** | | **~$411/month** |

> **vs. previous:** Single EC2 t3.large ($70) + manual everything = $70/month BUT 3 outages × $8K = $24,000/quarter lost revenue.  
> **ROI:** $341/month investment eliminates $96K/year revenue risk.

---

## Prerequisites

```bash
# Install required tools
brew install terraform awscli

# Configure AWS credentials
aws configure
# AWS Access Key ID: [your key]
# Default region: us-east-1

# Verify Terraform version
terraform version  # Requires >= 1.6
```

---

## Deploy

```bash
# 1. Clone and initialize
git clone https://github.com/vanessaawo/ha-wordpress-terraform
cd ha-wordpress-terraform
terraform init

# 2. Create S3 backend (run once)
aws s3 mb s3://vanessa-terraform-state --region us-east-1
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# 3. Review execution plan
terraform plan -var="environment=prod" -out=tfplan

# 4. Deploy (takes ~15-20 minutes)
terraform apply tfplan

# 5. Get outputs
terraform output cloudfront_domain
terraform output cloudwatch_dashboard_url
```

---

## Key Outputs After Deployment

```
cloudfront_domain       = "abc123.cloudfront.net"
alb_dns_name            = "ha-wordpress-prod-alb-123456.us-east-1.elb.amazonaws.com"
asg_name                = "ha-wordpress-prod-asg"
s3_media_bucket         = "ha-wordpress-prod-media-123456789012"
cloudwatch_dashboard_url = "https://console.aws.amazon.com/cloudwatch/..."
```

---

## Testing Resilience

```bash
# Test 1: AZ failure simulation — terminate all instances in one AZ
aws ec2 terminate-instances \
  --instance-ids $(aws ec2 describe-instances \
    --filters "Name=tag:aws:autoscaling:groupName,Values=ha-wordpress-prod-asg" \
              "Name=availability-zone,Values=us-east-1a" \
    --query "Reservations[].Instances[].InstanceId" --output text)
# Expected: ASG replaces instances in <5 min, ALB routes to healthy AZs immediately

# Test 2: RDS failover
aws rds reboot-db-instance \
  --db-instance-identifier ha-wordpress-prod-mysql \
  --force-failover
# Expected: < 2 minute failover, WordPress reconnects via same DNS endpoint

# Test 3: Load test (requires k6 or Apache Bench)
ab -n 10000 -c 200 https://your-cloudfront-domain.com/
# Expected: ASG scales out, CloudFront cache hits reduce origin load

# Test 4: WAF — confirm rate limiting
for i in {1..2500}; do curl -s https://your-domain.com/ -o /dev/null; done
# Expected: 403 after 2000 requests/5 min
```

---

## Operational Runbooks

### Runbook 1: High CPU Alert
```bash
# 1. Check ASG activity
aws autoscaling describe-scaling-activities --auto-scaling-group-name ha-wordpress-prod-asg

# 2. Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value=ha-wordpress-prod-asg \
  --statistics Average --period 60 --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)

# 3. If scaling is stuck, manually force scale-out
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name ha-wordpress-prod-asg \
  --desired-capacity 6
```

### Runbook 2: RDS High CPU (>80%)
```bash
# 1. Check Performance Insights — top SQL
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXX \
  --metric-queries '[{"Metric":"db.load.avg","GroupBy":{"Group":"db.sql","Limit":5}}]' \
  --start-time $(date -u -v-1H +%s) --end-time $(date -u +%s) --period-in-seconds 60

# 2. Enable slow query log (if not already)
aws rds modify-db-parameter-group \
  --db-parameter-group-name ha-wordpress-prod-mysql8 \
  --parameters "ParameterName=slow_query_log,ParameterValue=1,ApplyMethod=immediate"

# 3. If persistent, add read replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier ha-wordpress-prod-mysql-reader \
  --source-db-instance-identifier ha-wordpress-prod-mysql \
  --db-instance-class db.t3.medium
```

---

## Project Structure

```
01-ha-wordpress-terraform/
├── main.tf                    # Root module — wires all modules together
├── variables.tf               # Input variables with validation
├── outputs.tf                 # Key resource outputs
├── modules/
│   ├── vpc/                   # VPC, subnets, IGW, NAT GWs, route tables, flow logs
│   ├── security/              # KMS, ACM, security groups, WAF, IAM roles
│   ├── compute/               # ALB, Launch Template, ASG, scaling policies
│   ├── database/              # RDS Multi-AZ, parameter group, Secrets Manager, Backup
│   ├── cdn/                   # CloudFront, S3 media bucket, Route 53 records
│   └── monitoring/            # CloudWatch alarms, SNS, dashboard
└── docs/
    └── architecture.md
```

---

## Skills Demonstrated

- **Infrastructure as Code:** Terraform modules, remote state, input validation, lifecycle rules
- **High Availability:** Multi-AZ at every layer, no single point of failure
- **Security:** Defense-in-depth (WAF → CloudFront → ALB → SG → DB SG), IMDSv2, VPC endpoints, KMS
- **Cost optimization:** gp3 storage, S3 lifecycle, CloudFront PriceClass_100, scheduled scaling
- **Observability:** CloudWatch alarms on SLO-relevant metrics (latency p99, 5xx rate, RDS CPU)
- **Operations:** Launch Template instance refresh for zero-downtime deployments, runbooks

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
