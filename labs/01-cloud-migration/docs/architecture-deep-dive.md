# Lab 01: Enterprise Cloud Migration — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** On-premises monolith → AWS containerized microservices, end-to-end

---

## What This Migration Solves

A legacy on-premises monolith running at 94% uptime with $45,000/month in infrastructure costs and two-week provisioning cycles is not a technology problem — it's a business constraint. The architecture limits deployment frequency, eliminates disaster recovery, and makes scaling a procurement exercise. Migration to AWS with ECS Fargate doesn't just reduce costs; it changes the operational model from "manage hardware" to "manage workloads."

---

## Pre-Migration: Discovery and Assessment

Before writing a single line of Terraform, map the current state and categorize every component against the 6 Rs framework:

| Component | Current State | Migration Strategy | Why |
|-----------|--------------|-------------------|-----|
| Application server | Single physical server | Re-architect → ECS Fargate | Stateless app suits containerization |
| Oracle database | On-prem single instance | Re-platform → Aurora PostgreSQL | MySQL-compatible, managed Multi-AZ |
| Static assets | Served from app server | Re-locate → S3 + CloudFront | Decouples CDN from compute |
| Batch jobs | Cron on app server | Re-architect → ECS scheduled tasks | Independent scaling |
| File storage | NAS | Re-platform → EFS | Managed, multi-AZ, NFS-compatible |

**Why not "Lift and Shift" (Re-host)?**  
Re-hosting an EC2 replica of the on-premises server achieves the same 94% uptime on a newer machine. It eliminates hardware maintenance costs but preserves the operational model: a single instance that becomes the single point of failure. Re-architecting to ECS Fargate adds 4–6 weeks of engineering time upfront but eliminates the SPOF and enables auto-scaling — the two root causes of the client's outages.

---

## Step-by-Step: Infrastructure Provisioning

### Step 1 — VPC Network Foundation

Terraform creates `VPC 10.0.0.0/16` with 4 subnets across 2 AZs.

```
VPC: 10.0.0.0/16
├── Public Subnet AZ-a:   10.0.1.0/24   ← ALB, NAT Gateway
├── Public Subnet AZ-b:   10.0.2.0/24   ← ALB, NAT Gateway
├── Private Subnet AZ-a:  10.0.10.0/24  ← ECS tasks, RDS
└── Private Subnet AZ-b:  10.0.20.0/24  ← ECS tasks, RDS
```

**Why 2 AZs, not 1?**  
An AZ is a physically separate data center. Any single AZ can experience a power, networking, or cooling failure. With compute and data in 2 AZs, the surviving AZ continues serving traffic. AWS SLA guarantees at least one AZ remains operational during any regional event. Two AZs is the minimum for a meaningful availability improvement over on-premises.

**Why private subnets for ECS tasks?**  
ECS tasks in public subnets receive internet-accessible IP addresses. Any container vulnerability, misconfigured security group, or exposed port becomes internet-reachable. Private subnets have no internet route — all inbound traffic must traverse the ALB (where security groups and WAF rules are applied), and outbound traffic routes through NAT Gateways. This eliminates direct-access attack surface without affecting application functionality.

**Why a NAT Gateway per AZ?**  
A single NAT Gateway in one AZ means: if that AZ fails, ECS tasks in the other AZ cannot reach the internet (for ECR image pulls, CloudWatch logging, Secrets Manager calls). Two NAT Gateways cost ~$65/month extra but provide AZ-independent egress. For a production migration, this is the correct trade-off.

### Step 2 — Application Load Balancer

The ALB sits in the public subnets across both AZs, receiving all inbound traffic.

**ALB configuration:**
- **Listener 80 → 443 redirect:** HTTP traffic automatically redirected — no plaintext sessions
- **Listener 443 with ACM certificate:** TLS terminated at the ALB; ECS tasks communicate over HTTP internally (no per-task certificate management)
- **Health check:** `GET /health` every 30 seconds; 3 consecutive failures mark a target unhealthy and remove it from rotation
- **Target group:** forwards to ECS tasks by IP (not instance ID — Fargate doesn't have instances)

**Why ALB over NLB (Network Load Balancer)?**  
NLB operates at Layer 4 (TCP). ALB operates at Layer 7 (HTTP). For this application: path-based routing (routing `/api/*` to the API containers and `/static/*` to a static server), host-based routing, and HTTP header inspection are all Layer 7 capabilities. NLB provides lower latency but none of the application-layer routing. For a web application migration, ALB is the correct choice.

### Step 3 — ECR Container Registry

Each service has a private ECR repository.

**ECR configuration:**
- **Image tag mutability: IMMUTABLE** — once pushed, `app:1.0.3` always refers to exactly that image. Mutable tags allow overwriting, which means the CI pipeline could deploy a different image than the one that passed testing.
- **Scan on push: enabled** — ECR runs a vulnerability scan against the image immediately on push. Critical CVEs appear in the console and can trigger SNS alerts before the image is deployed.
- **Lifecycle policy:** keep last 30 images, delete untagged images older than 1 day. Prevents ECR storage from growing unbounded.

### Step 4 — Multi-Stage Docker Build

```dockerfile
# Stage 1: Build (includes compiler, test tools, dev dependencies)
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Stage 2: Runtime (minimal, no build tools)
FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER node    ← non-root
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

**Why multi-stage?**  
Stage 1 includes compilers, test runners, build tools — all necessary for building but a security and size liability at runtime. A `node:20` full image is ~1GB; `node:20-alpine` with only production dependencies is ~150MB. Smaller images:
- Pull faster (less time from ECR to running container)
- Reduce attack surface (no compiler or test tools to exploit)
- Lower ECR storage costs

**Why `USER node`?**  
Running as root inside a container means a container escape vulnerability gives the attacker root on the host. Running as a non-root user limits the blast radius.

### Step 5 — ECS Fargate Cluster and Task Definition

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512   # 0.5 vCPU
  memory                   = 1024  # 1 GB
  
  container_definitions = jsonencode([{
    name  = "app"
    image = "${aws_ecr_repository.app.repository_url}:latest"
    
    portMappings = [{ containerPort = 3000, protocol = "tcp" }]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"  = "/ecs/app"
        "awslogs-region" = "us-west-2"
        "awslogs-stream-prefix" = "app"
      }
    }
    
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    
    secrets = [{
      name      = "DB_PASSWORD"
      valueFrom = aws_secretsmanager_secret.db_password.arn
    }]
  }])
}
```

**Why Fargate over EC2 launch type?**  
EC2 launch type requires managing EC2 instances: choosing instance types, patching AMIs, managing node capacity, and handling EC2 scaling separately from task scaling. Fargate abstracts all of this — you specify CPU and memory per task, and AWS provisions the compute. For a client migrating from on-premises specifically to eliminate server management, Fargate completes the goal. EC2 launch type would move the "manage servers" problem from on-premises to AWS.

**Why `awsvpc` networking?**  
`awsvpc` gives each task its own ENI (Elastic Network Interface) with a unique IP address. Security groups are attached to the ENI, not the host. This provides task-level network isolation — a security group rule can reference the task's security group directly, without routing through host-level security groups. It's required for Fargate.

**Why Secrets Manager instead of environment variables?**  
Environment variables appear in CloudWatch logs, ECS task metadata, and any debugging output. The `DB_PASSWORD` in an environment variable is exposed to any operator who runs `aws ecs describe-tasks`. Secrets Manager stores the value encrypted (KMS), provides access via IAM policy, rotates automatically, and logs every access in CloudTrail. The `secrets` block in the task definition injects the value as an environment variable at container start time, decrypted by ECS — the application code never sees the ARN.

### Step 6 — ECS Service with Auto Scaling

```hcl
resource "aws_ecs_service" "app" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 3000
  }
  
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
}
```

**Why `desired_count = 2`?**  
One task is a single point of failure. ECS distributes 2 tasks across 2 AZs (one per AZ if `placementStrategies` are configured or if Fargate's default spread strategy is used). Any single task failure, AZ failure, or deployment causes the remaining task to continue serving traffic.

**Why `deployment_minimum_healthy_percent = 100`?**  
During a deployment, ECS replaces tasks. With `100`, ECS must maintain at least 100% of `desired_count` during the rollout — it starts new tasks before stopping old ones. Combined with `maximum_percent = 200`, ECS runs 4 tasks temporarily (2 old + 2 new), performs health checks, then stops the old tasks. Zero-downtime rolling deployments.

### Step 7 — Aurora PostgreSQL Multi-AZ

```hcl
resource "aws_rds_cluster" "main" {
  cluster_identifier     = "app-cluster"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  database_name          = "app"
  master_username        = "admin"
  master_password        = random_password.db.result
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn
  
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"  # 3-4 AM UTC
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  skip_final_snapshot = false
  final_snapshot_identifier = "app-final-${formatdate("YYYY-MM-DD", timestamp())}"
}

resource "aws_rds_cluster_instance" "instances" {
  count               = 2  # 1 writer + 1 reader
  cluster_identifier  = aws_rds_cluster.main.id
  instance_class      = "db.t3.medium"
  engine              = "aurora-postgresql"
}
```

**Why Aurora PostgreSQL over standard RDS PostgreSQL?**

| Feature | Aurora PostgreSQL | RDS PostgreSQL |
|---------|-----------------|----------------|
| Failover | < 30 seconds | 60–120 seconds |
| Replication | Shared storage (zero data loss) | Async log shipping (1-2 WAL lag) |
| Storage | Auto-scales to 128TB | Requires manual resize |
| Read replicas | Up to 15 | Up to 5 |
| Speed claim | 3× faster than standard PostgreSQL | Standard |

The critical difference is the storage architecture. Aurora uses a distributed shared storage layer — both writer and reader access the same physical storage across 6 copies in 3 AZs. Failover switches the primary pointer in the storage layer rather than waiting for data to replicate to the standby. This is why failover is < 30 seconds (vs 60–120 for standard RDS).

**Why `backup_retention_period = 7`?**  
7-day automated backups provide a PITR (Point-in-Time Recovery) window — restore to any second within the last 7 days. If a developer runs `DELETE FROM orders WHERE status != 'complete'` with a bug in the WHERE clause and deletes all orders, PITR can restore the database to 30 seconds before the query ran. 1-day retention means any 1+ day-old data loss is unrecoverable; 7 days covers weekend incidents discovered Monday morning.

### Step 8 — CloudWatch Monitoring

```hcl
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

**Why `evaluation_periods = 2`?**  
A single high-CPU sample could be a momentary spike (garbage collection, a large request). Requiring 2 consecutive periods (2 minutes) reduces false alarms. By the time the alarm fires, the condition has been sustained — indicating a real problem rather than a transient spike.

---

## Migration Execution: The 4-Phase Approach

### Phase 1 — Assess (Weeks 1–2)
- Inventory all application dependencies (external APIs, file system paths, environment variables)
- Profile the database: schema, table sizes, query patterns, connection pool configuration
- Identify hardcoded server IPs or hostnames in the application code
- Run load testing to establish baseline performance metrics

### Phase 2 — Plan (Weeks 3–4)
- Define the cutover strategy: direct switch vs. DNS-based gradual migration
- Write the rollback plan: how to revert to on-premises if migration fails
- Lower DNS TTL to 60 seconds (from typically 3600) — 48 hours before cutover
- Set up AWS environment and test with production-like data

### Phase 3 — Migrate (Week 5)
- Use AWS DMS (Database Migration Service) for live database migration with minimal downtime
  - DMS performs initial load of the database while the application continues running on-premises
  - Ongoing replication keeps the RDS instance current
  - Cutover: flip the application to AWS while DMS maintains sync — cutover window is minutes
- Deploy the ECS application and validate against the migrated database
- DNS cutover: change the A record to point to the ALB

### Phase 4 — Optimize (Ongoing)
- Right-size ECS tasks based on actual CPU/memory utilization (not estimated)
- Configure Auto Scaling based on observed traffic patterns
- Evaluate Reserved Instances for Aurora (1-year RI = ~40% savings)
- Review CloudWatch dashboards for unexpected patterns

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **IaC with Terraform:** Entire environment recreated in 30 minutes from `terraform apply`. Changes are reviewed in `terraform plan` before applying — no console-click drift
- **CloudWatch structured logging:** All container logs in CloudWatch Logs with search and filter. No `kubectl exec` or SSH to access logs
- **Deployment automation:** ECS rolling deployment is automatic — no deployment scripts, no manual steps

### Security
- **Private subnets:** ECS tasks and Aurora have no public IPs — not internet-accessible
- **ACM certificate + HTTPS redirect:** No plaintext traffic
- **Secrets Manager:** Database credentials never in environment variables or code
- **IMDSv2 on NAT Gateways:** Even AWS-managed infrastructure benefits from v2 metadata
- **ECR scan on push:** Container vulnerabilities caught before deployment

### Reliability
- **Multi-AZ ECS:** Tasks spread across 2 AZs — single AZ failure maintains capacity
- **Multi-AZ NAT Gateways:** Egress works regardless of which AZ fails
- **Aurora failover < 30 seconds:** Database tier recovers automatically
- **ALB health checks:** Unhealthy tasks removed from rotation within 30 seconds
- **Zero-downtime deployments:** `minimum_healthy_percent = 100` prevents deployment outages

### Performance Efficiency
- **Fargate resource-right sizing:** Task CPU/memory specified per service requirement, not per physical server
- **Aurora reader endpoint:** Read-heavy queries routed to the reader instance — writer handles only writes
- **CloudFront for static assets:** Future phase; reduces ALB/ECS load for static content
- **Connection pooling:** Application-level connection pool prevents Aurora connection exhaustion

### Cost Optimization
- **35% cost reduction:** $45,000 → $29,250/month
- **Fargate pay-per-task:** No idle capacity — tasks run when needed, stopped when not
- **Aurora pay-per-storage:** Storage auto-scales; no over-provisioning needed
- **Reserved Instances (post-migration):** 1-year Aurora RI provides ~40% savings on stable baseline

### Sustainability
- **Fargate:** AWS manages the physical infrastructure for efficiency — shared hardware, higher utilization
- **Auto Scaling:** Scales down during off-peak hours, reducing compute consumption
- **Graviton-compatible Fargate:** Fargate on ARM64 (Graviton2) is available and costs 20% less with better energy efficiency

---

## Key Architectural Insight

The central principle of this migration is **separating what the application does from how it runs**. On-premises, the application and its runtime (OS, server, networking) were the same physical machine. On AWS with Fargate, the application runs as a container and the runtime is AWS's responsibility. This separation is what enables: zero-downtime deployments (ECS can replace the runtime while the application code stays the same), auto-scaling (ECS can run 2 or 20 tasks without the application knowing), and managed failover (Aurora can switch the storage writer without the application reconnecting to a different endpoint).

The migration is not just a cost exercise — it's a change in operational model from "manage hardware" to "declare requirements."

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
