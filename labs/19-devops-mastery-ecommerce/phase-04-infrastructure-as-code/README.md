# Phase 4: Infrastructure as Code

**Difficulty:** Intermediate | **Time:** 6-8 hours | **Prerequisites:** Phase 3

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

This phase provisions the entire AWS infrastructure using Terraform modules. Every resource is codified, version-controlled, and reproducible. The infrastructure supports the e-commerce platform with high availability across 3 Availability Zones.

### Infrastructure Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Region: us-east-1                                          │
│                                                                 │
│  VPC: 10.0.0.0/16                                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  AZ: us-east-1a    AZ: us-east-1b    AZ: us-east-1c     │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │Public Subnet │  │Public Subnet │  │Public Subnet │   │  │
│  │  │10.0.1.0/24   │  │10.0.2.0/24   │  │10.0.3.0/24   │   │  │
│  │  │  NAT GW      │  │  NAT GW      │  │  NAT GW      │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │Private Subnet│  │Private Subnet│  │Private Subnet│   │  │
│  │  │10.0.10.0/24  │  │10.0.20.0/24  │  │10.0.30.0/24  │   │  │
│  │  │  EKS Nodes   │  │  EKS Nodes   │  │  EKS Nodes   │   │  │
│  │  │  RDS Replica │  │  RDS Primary │  │  RDS Replica │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐       │
│  │ EKS Cluster │  │Aurora PgSQL │  │ElastiCache Redis │       │
│  │ Bottlerocket│  │ Multi-AZ    │  │ 3-node cluster   │       │
│  │ 3-20 nodes  │  │ 35d backup  │  │ r6g.large        │       │
│  └─────────────┘  └─────────────┘  └──────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### Module Structure

```
phase-04-infrastructure-as-code/
├── modules/
│   ├── vpc/main.tf          # VPC, subnets, NAT Gateways, VPC endpoints
│   ├── eks/main.tf          # EKS cluster, managed node groups
│   └── rds/main.tf          # Aurora PostgreSQL, multi-AZ
└── environments/
    └── production.tfvars    # Production environment values
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Terraform | 1.6+ | `brew install terraform` |
| AWS CLI | 2.x | `brew install awscli` |
| kubectl | 1.28+ | `brew install kubectl` |

### AWS Configuration

```bash
# Configure AWS credentials
aws configure
# Region: us-east-1
# Output: json

# Verify access
aws sts get-caller-identity
```

### Remote State Backend (one-time setup)

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://ecommerce-terraform-state-$(aws sts get-caller-identity --query Account --output text)

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

---

## 3. Step-by-Step Implementation

### Step 1: Create the VPC Module

The VPC module creates the network foundation — a `/16` VPC with public and private subnets across 3 AZs, NAT Gateways for outbound internet access, and VPC endpoints for private AWS API access.

```bash
cd modules/vpc
```

Key resources created:
- **VPC** — `10.0.0.0/16` with DNS support enabled
- **3 Public Subnets** — For load balancers and NAT Gateways
- **3 Private Subnets** — For EKS nodes, RDS, and ElastiCache
- **3 NAT Gateways** — One per AZ for high availability (private subnet outbound)
- **Internet Gateway** — For public subnet internet access
- **VPC Endpoints** — S3 and ECR endpoints to keep traffic within AWS

```bash
terraform init
terraform plan -var-file=../../environments/production.tfvars
```

### Step 2: Create the EKS Module

The EKS module provisions the Kubernetes cluster with managed node groups running Bottlerocket OS.

Key resources created:
- **EKS Cluster** — Kubernetes control plane (managed by AWS)
- **Managed Node Group** — Bottlerocket nodes with auto-scaling (3-20 nodes)
- **IAM Roles** — Cluster role, node role, and IRSA (IAM Roles for Service Accounts)
- **Security Groups** — Cluster and node security groups
- **OIDC Provider** — For IRSA integration (pods assume IAM roles)

```bash
# After VPC is created:
cd modules/eks
terraform init
terraform plan -var-file=../../environments/production.tfvars
```

### Step 3: Create the RDS Module

The RDS module provisions Aurora PostgreSQL with multi-AZ deployment.

Key resources created:
- **Aurora Cluster** — PostgreSQL-compatible with automated failover
- **Writer Instance** — Primary database in one AZ
- **Reader Instance(s)** — Read replicas in other AZs
- **Subnet Group** — Places RDS in private subnets
- **Security Group** — Allows access only from EKS nodes
- **Parameter Group** — PostgreSQL tuning parameters
- **Automated Backups** — 35-day retention with point-in-time recovery

### Step 4: Initialize and Apply

```bash
cd environments

# Initialize with remote backend
terraform init \
  -backend-config="bucket=ecommerce-terraform-state-ACCOUNT_ID" \
  -backend-config="key=production/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-state-lock"

# Preview changes
terraform plan -var-file=production.tfvars

# Apply (review the plan carefully before confirming)
terraform apply -var-file=production.tfvars
```

**Expected output (abbreviated):**

```
Apply complete! Resources: 47 added, 0 changed, 0 destroyed.

Outputs:
  vpc_id          = "vpc-0abc123def456"
  eks_cluster_name = "ecommerce-production"
  rds_endpoint    = "ecommerce-production.cluster-xyz.us-east-1.rds.amazonaws.com"
```

### Step 5: Configure kubectl

```bash
aws eks update-kubeconfig \
  --name ecommerce-production \
  --region us-east-1

# Verify cluster access
kubectl get nodes
# Expected: 5 nodes in Ready state across 3 AZs
```

---

## 4. Configuration Walkthrough

### `environments/production.tfvars` — Line by Line

```hcl
project     = "ecommerce"          # Resource naming prefix
environment = "production"          # Environment tag for all resources
region      = "us-east-1"          # Primary AWS region

# ── VPC Configuration ──
vpc_cidr             = "10.0.0.0/16"    # 65,536 IPs — room for growth
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]  # 3 AZs for HA
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]  # 254 IPs each
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]    # For LBs/NAT GWs

# ── EKS Configuration ──
eks_node_instance_types = ["m5.large"]   # 2 vCPU, 8 GB RAM — balanced compute
eks_node_min_size       = 3              # Minimum 1 node per AZ
eks_node_max_size       = 20             # Scale ceiling for peak traffic
eks_node_desired_size   = 5              # Steady-state capacity

# ── RDS Configuration ──
rds_instance_class         = "db.r6g.large"   # Memory-optimized for PostgreSQL
rds_backup_retention_days  = 35               # 35 days of point-in-time recovery
rds_deletion_protection    = true              # Prevent accidental deletion

# ── ElastiCache Configuration ──
elasticache_node_type      = "cache.r6g.large"  # Memory-optimized for Redis
elasticache_num_cache_nodes = 3                  # 1 primary + 2 replicas
```

### VPC Module — Key Design Decisions

```hcl
# modules/vpc/main.tf (key excerpts)

# Public subnets get auto-assigned public IPs and route through IGW
# Private subnets route through NAT Gateway (one per AZ for HA)

# VPC Endpoints reduce data transfer costs and improve latency:
# - S3 Gateway Endpoint: free, keeps S3 traffic off the internet
# - ECR Endpoints: container image pulls stay within the VPC
```

### EKS Module — Key Design Decisions

```hcl
# modules/eks/main.tf (key excerpts)

# Bottlerocket OS: security-focused, minimal surface area, auto-updates
# Managed node groups: AWS handles node provisioning and lifecycle
# OIDC Provider: enables IRSA — pods assume IAM roles without static credentials
```

### RDS Module — Key Design Decisions

```hcl
# modules/rds/main.tf (key excerpts)

# Aurora PostgreSQL: up to 5x faster than standard PostgreSQL
# Multi-AZ: automatic failover to a reader in another AZ (< 30 seconds)
# Encryption: at-rest encryption with KMS, in-transit encryption with TLS
# 35-day backup retention: exceeds most compliance requirements
```

---

## 5. Verification Checklist

- [ ] `terraform init` succeeds with remote state backend
- [ ] `terraform plan` shows expected resources (approximately 47)
- [ ] `terraform apply` completes without errors
- [ ] VPC created with correct CIDR: `aws ec2 describe-vpcs --filters Name=tag:Name,Values=ecommerce-production`
- [ ] 3 public + 3 private subnets across 3 AZs
- [ ] NAT Gateways are active in each AZ
- [ ] EKS cluster is ACTIVE: `aws eks describe-cluster --name ecommerce-production --query cluster.status`
- [ ] EKS nodes are Ready: `kubectl get nodes`
- [ ] Aurora cluster is available: `aws rds describe-db-clusters --query 'DBClusters[0].Status'`
- [ ] State file stored in S3: `aws s3 ls s3://ecommerce-terraform-state-ACCOUNT_ID/production/`
- [ ] State locking works: `terraform plan` does not warn about missing lock

---

## 6. Troubleshooting

### Terraform init fails: "Backend configuration changed"

```bash
# If you changed the backend configuration:
terraform init -reconfigure

# If you need to migrate state:
terraform init -migrate-state
```

### EKS nodes stuck in NotReady

```bash
# Check node status
kubectl describe node <node-name>

# Common causes:
# 1. Node IAM role missing required policies (AmazonEKSWorkerNodePolicy, etc.)
# 2. Node security group missing cluster communication rules
# 3. VPC CNI plugin not installed
kubectl get pods -n kube-system | grep aws-node
```

### Aurora cluster creation timeout

```bash
# Aurora clusters take 10-15 minutes to create
# Check status:
aws rds describe-db-clusters \
  --db-cluster-identifier ecommerce-production \
  --query 'DBClusters[0].Status'

# If stuck in "creating" for >20 minutes, check CloudTrail for errors
```

### "Error: Insufficient capacity" on node group

```bash
# Try adding more instance types to the allowed list
eks_node_instance_types = ["m5.large", "m5a.large", "m6i.large"]
# This gives AWS more options to find available capacity
```

### State lock conflict

```bash
# If a previous apply was interrupted, the lock may be stuck
terraform force-unlock <LOCK_ID>

# Get the lock ID from the error message
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **EKS vs. self-managed K8s** | EKS (managed) | kOps / kubeadm | AWS manages the control plane — no master node patching. Trade-off: less control, vendor lock-in. |
| **Bottlerocket vs. Amazon Linux 2** | Bottlerocket | Amazon Linux 2 | Minimal OS purpose-built for containers, auto-updates. Trade-off: no SSH, limited debugging tools. |
| **Aurora vs. standard RDS** | Aurora PostgreSQL | RDS PostgreSQL | Up to 5x faster, built-in replication, Global Database support (Phase 12). Trade-off: higher cost. |
| **3 NAT GWs vs. 1 NAT GW** | 3 (one per AZ) | 1 shared NAT GW | No single point of failure. Trade-off: 3x NAT Gateway cost (~$100/month). |
| **Terraform modules vs. flat** | Modular | Single main.tf | Reusable, testable, clear boundaries. Trade-off: slightly more complex directory structure. |
| **S3 + DynamoDB state** | Remote state with locking | Local state | Team collaboration, state locking prevents conflicts. Trade-off: requires initial setup. |

---

## 8. Production Considerations

- **State file security** — Enable S3 bucket versioning and encryption; restrict access via IAM
- **Terraform workspaces** — Use workspaces or separate state files for dev/staging/production
- **Plan review** — Always run `terraform plan` and review before `terraform apply`; integrate into CI (Phase 5)
- **Drift detection** — Schedule periodic `terraform plan` runs to detect manual changes
- **Cost monitoring** — NAT Gateways, EKS nodes, and Aurora are the primary cost drivers; monitor with Phase 13 FinOps
- **Tagging strategy** — All resources should be tagged with `project`, `environment`, `team`, and `cost-center`
- **Secrets management** — Database passwords should be generated and stored in Secrets Manager, not in tfvars

---

## 9. Next Phase

**[Phase 5: CI/CD Pipelines →](../phase-05-cicd/README.md)**

With infrastructure provisioned, Phase 5 creates GitHub Actions pipelines that automatically lint, test, build, scan, and deploy the microservices — including path-filtered monorepo builds and Trivy container scanning.

---

[← Phase 3: Containerization](../phase-03-containerization/README.md) | [Back to Project Overview](../README.md) | [Phase 5: CI/CD Pipelines →](../phase-05-cicd/README.md)
