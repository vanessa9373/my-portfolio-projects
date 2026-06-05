# Phase 12: Multi-Region & Disaster Recovery

**Difficulty:** Expert | **Time:** 8-10 hours | **Prerequisites:** Phase 11

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

This phase extends the platform to a multi-region architecture for disaster recovery. The primary region (us-east-1) handles all traffic under normal conditions, while a warm standby in the secondary region (eu-west-1) is ready to take over within 5 minutes if the primary fails.

### Multi-Region Architecture

```
                          Route 53 (Failover Policy)
                          ┌──────────────────────┐
                          │  api.ecommerce.com   │
                          │  TTL: 60s             │
                          └────────┬─────────────┘
                        ┌──────────┴──────────┐
                        ▼                     ▼
              ┌──────────────────┐  ┌──────────────────┐
              │  us-east-1       │  │  eu-west-1       │
              │  PRIMARY         │  │  SECONDARY       │
              │  (Active)        │  │  (Warm Standby)  │
              │                  │  │                  │
              │  EKS Cluster     │  │  EKS Cluster     │
              │  6 services      │  │  6 services      │
              │  (full scale)    │  │  (min replicas)  │
              │                  │  │                  │
              │  Aurora Writer   │◄─┤  Aurora Reader   │
              │                  │  │  (< 100ms lag)   │
              │  ElastiCache     │  │  ElastiCache     │
              │  Primary         │  │  Global Store    │
              └──────────────────┘  └──────────────────┘
```

### Key Metrics

| Metric | Target | How |
|--------|--------|-----|
| **RPO** (Recovery Point Objective) | < 1 minute | Aurora Global Database replication lag < 100ms |
| **RTO** (Recovery Time Objective) | < 5 minutes | Automated Route 53 failover + pre-scaled standby |
| **DNS TTL** | 60 seconds | Clients resolve to new region within 1-2 minutes |
| **Failover drills** | Quarterly | Validated via the failover runbook |

### Directory Structure

```
phase-12-multi-region/
├── terraform/
│   └── route53.tf              # Route 53 failover configuration
└── dr-runbooks/
    └── failover-runbook.md     # 670-line comprehensive failover runbook
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Terraform | 1.6+ | Installed in Phase 4 |
| AWS CLI | 2.x | Installed in Phase 4 |
| kubectl | 1.28+ | Installed in Phase 4 |
| Velero | 1.12+ | `brew install velero` |

### Secondary Region Setup

Before configuring Route 53 failover, the secondary region needs:

```bash
# 1. EKS cluster in eu-west-1 (apply Phase 4 Terraform with eu-west-1 region)
# 2. Aurora Global Database secondary cluster
# 3. ElastiCache Global Datastore secondary
# 4. ECR image replication to eu-west-1
# 5. Velero backup configured for cross-region restore
```

---

## 3. Step-by-Step Implementation

### Step 1: Create Route 53 Health Checks

Apply the Terraform configuration:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates:
- Health checks polling the primary and secondary ALB endpoints every 10 seconds
- Failover routing policy with PRIMARY and SECONDARY records
- Alias records pointing to each region's ALB

### Step 2: Configure Aurora Global Database

```bash
# Create the global database cluster
aws rds create-global-cluster \
  --global-cluster-identifier ecommerce-global \
  --source-db-cluster-identifier arn:aws:rds:us-east-1:ACCOUNT:cluster:ecommerce-production \
  --region us-east-1

# Add a secondary cluster in eu-west-1
aws rds create-db-cluster \
  --db-cluster-identifier ecommerce-secondary \
  --global-cluster-identifier ecommerce-global \
  --engine aurora-postgresql \
  --engine-version 15.4 \
  --region eu-west-1
```

### Step 3: Configure Velero for Cross-Region Backup

```bash
# Install Velero with AWS plugin
velero install \
  --provider aws \
  --bucket ecommerce-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --plugins velero/velero-plugin-for-aws:v1.8.0

# Create a scheduled backup (every 15 minutes)
velero schedule create ecommerce-prod \
  --schedule="*/15 * * * *" \
  --include-namespaces production \
  --ttl 720h
```

### Step 4: Configure S3 Cross-Region Replication

```bash
# Enable versioning on source bucket (required for CRR)
aws s3api put-bucket-versioning \
  --bucket ecommerce-assets-us-east-1 \
  --versioning-configuration Status=Enabled

# Create replication configuration
aws s3api put-bucket-replication \
  --bucket ecommerce-assets-us-east-1 \
  --replication-configuration file://s3-replication.json
```

### Step 5: Validate the Failover Runbook

The failover runbook (`dr-runbooks/failover-runbook.md`) is a 670-line document that covers every aspect of a regional failover. Read it thoroughly — it serves as both documentation and the operational procedure for production incidents.

**[Read the full Failover Runbook →](./dr-runbooks/failover-runbook.md)**

The runbook covers:
1. **Prerequisites checklist** — Infrastructure, data, networking, and team readiness (60+ items)
2. **Automated failover** — How Route 53 health checks trigger automatic DNS failover
3. **Manual failover** — Step-by-step procedure when automated failover doesn't trigger
4. **Aurora Global Database failover** — Planned and unplanned database failover procedures
5. **Velero restore** — Kubernetes resource restoration from backup
6. **DNS propagation verification** — Multi-provider DNS resolution checks
7. **Validation checklist** — Health, API, data integrity, latency, and monitoring verification
8. **Rollback procedure** — How to fail back to the primary region
9. **Communication templates** — Internal (Slack), external (status page), and customer notifications
10. **Post-incident review template** — Timeline, RCA, 5 Whys, action items, and metrics

### Step 6: Run a Failover Drill

```bash
# Simulate primary region failure by disabling the health check
aws route53 update-health-check \
  --health-check-id HC_PRIMARY_REGION_ID \
  --disabled

# Monitor DNS resolution
watch -n 5 "dig +short api.ecommerce.com @8.8.8.8"

# Expected: IP changes from primary ALB to secondary ALB within 1-2 minutes

# Verify services in secondary region
kubectl --context eu-west-1-ecommerce-prod get pods -n production

# Re-enable primary health check after drill
aws route53 update-health-check \
  --health-check-id HC_PRIMARY_REGION_ID \
  --no-disabled
```

---

## 4. Configuration Walkthrough

### `terraform/route53.tf` — Line by Line

```hcl
# ── Health Check: Primary Region ──
resource "aws_route53_health_check" "primary" {
  fqdn              = "api-us-east-1.ecommerce.com"   # Primary ALB endpoint
  port               = 443                              # HTTPS
  type               = "HTTPS"
  resource_path      = "/health"                        # Health check path
  failure_threshold  = "3"                              # Mark unhealthy after 3 failures
  request_interval   = "10"                             # Check every 10 seconds
                                                         # 3 failures × 10s = 30s detection time

  tags = {
    Name = "ecommerce-primary-health-check"
  }
}

# ── Health Check: Secondary Region ──
resource "aws_route53_health_check" "secondary" {
  fqdn              = "api-eu-west-1.ecommerce.com"    # Secondary ALB endpoint
  port               = 443
  type               = "HTTPS"
  resource_path      = "/health"
  failure_threshold  = "3"
  request_interval   = "10"

  tags = {
    Name = "ecommerce-secondary-health-check"
  }
}

# ── DNS Record: Primary (Active) ──
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.ecommerce.com"
  type    = "A"

  alias {
    name                   = aws_lb.primary.dns_name    # Primary region ALB
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true                        # Use ALB's own health checks too
  }

  set_identifier  = "primary"
  failover_routing_policy {
    type = "PRIMARY"                                     # This is the default target
  }
  health_check_id = aws_route53_health_check.primary.id # Associated health check
}

# ── DNS Record: Secondary (Standby) ──
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.ecommerce.com"
  type    = "A"

  alias {
    name                   = aws_lb.secondary.dns_name  # Secondary region ALB
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }

  set_identifier  = "secondary"
  failover_routing_policy {
    type = "SECONDARY"                                   # Failover target
  }
  health_check_id = aws_route53_health_check.secondary.id
}
```

### Failover Timeline

```
T+0s    Primary region ALB stops responding
T+10s   First health check failure
T+20s   Second health check failure
T+30s   Third failure → Route 53 marks primary as UNHEALTHY
T+30s   Route 53 starts returning secondary ALB IP
T+90s   Most clients resolve to secondary (60s TTL)
T+120s  Full traffic shift to secondary region
```

---

## 5. Verification Checklist

- [ ] Route 53 health checks active for both regions: `aws route53 list-health-checks`
- [ ] Health checks polling successfully: `aws route53 get-health-check-status --health-check-id <id>`
- [ ] DNS resolves to primary region normally: `dig +short api.ecommerce.com`
- [ ] Aurora Global Database replication lag < 100ms:
  ```bash
  aws rds describe-global-clusters --global-cluster-identifier ecommerce-global
  ```
- [ ] Secondary EKS cluster is healthy: `kubectl --context eu-west-1 get nodes`
- [ ] Velero backups running on schedule: `velero backup get`
- [ ] S3 CRR is current: check replication metrics in CloudWatch
- [ ] Failover drill completed successfully (DNS switches within 2 minutes)
- [ ] Failback procedure tested (traffic returns to primary)
- [ ] Failover runbook reviewed and up to date
- [ ] Communication templates prepared for incidents
- [ ] Team has practiced the runbook at least once

---

## 6. Troubleshooting

### Route 53 health check stuck in UNKNOWN

```bash
# Check health check configuration
aws route53 get-health-check --health-check-id <id>

# Common causes:
# 1. Security group blocking Route 53 health checkers (IPs vary by region)
# 2. HTTPS certificate issues (expired, wrong domain)
# 3. /health endpoint returning non-200 status
```

### Aurora replication lag increasing

```bash
# Monitor replication lag
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicationLag \
  --dimensions Name=DBClusterIdentifier,Value=ecommerce-secondary \
  --period 60 --statistics Average \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --region eu-west-1

# High lag causes:
# 1. Heavy write load on primary
# 2. Network latency between regions
# 3. Secondary cluster under-provisioned
```

### DNS not propagating after failover

```bash
# Check from multiple DNS providers
dig +short api.ecommerce.com @8.8.8.8    # Google
dig +short api.ecommerce.com @1.1.1.1    # Cloudflare

# Check Route 53 change status
aws route53 get-change --id /change/C_CHANGE_ID

# If stuck, verify TTL is set to 60s (not the default 300s)
```

### Secondary region services not ready

```bash
# Scale up secondary region deployments
kubectl --context eu-west-1 scale deployment --all --replicas=3 -n production

# Wait for pods to be ready
kubectl --context eu-west-1 wait --for=condition=ready pod --all -n production --timeout=300s
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Active-passive vs. active-active** | Active-passive | Active-active | Simpler operations, lower cost. Trade-off: secondary region is underutilized. |
| **Route 53 failover vs. Global Accelerator** | Route 53 | Global Accelerator | DNS-based is simpler, no additional service. Trade-off: 60s DNS TTL delay vs. instant failover. |
| **Aurora Global vs. cross-region read replicas** | Aurora Global Database | Standard cross-region replicas | Sub-100ms replication, managed failover. Trade-off: higher cost than standard replicas. |
| **Warm standby vs. pilot light** | Warm standby (min replicas running) | Pilot light (infra only, no running pods) | Faster RTO (minutes vs. 30+ minutes). Trade-off: higher running cost for standby. |
| **60s DNS TTL** | 60 seconds | 300s (default) | Faster failover at cost of more DNS queries. Trade-off: slightly higher DNS query costs. |

---

## 8. Production Considerations

- **Quarterly drills** — Schedule failover drills every quarter; alternate between automated and manual procedures
- **Data consistency** — After unplanned failover, audit for data discrepancies between last successful replication and failover time
- **Cost optimization** — Secondary region runs at minimum capacity; scale up only during failover or drills
- **Certificate management** — Ensure TLS certificates are valid in both regions; use ACM with DNS validation for automatic renewal
- **CDN failover** — Configure CloudFront with both regional origins for static asset failover
- **Monitoring** — Set up cross-region monitoring so you can observe the secondary region from the primary (and vice versa)
- **Runbook maintenance** — Update the failover runbook after every drill or production incident

---

## 9. Next Phase

**[Phase 13: FinOps & Cost Optimization →](../phase-13-finops/README.md)**

With multi-region DR ensuring availability, Phase 13 focuses on cost — Karpenter for intelligent node provisioning with Spot instances, Kubecost for cost allocation and anomaly detection, achieving 40% cost reduction while maintaining performance.

---

[← Phase 11: Service Mesh](../phase-11-service-mesh/README.md) | [Back to Project Overview](../README.md) | [Phase 13: FinOps →](../phase-13-finops/README.md)
