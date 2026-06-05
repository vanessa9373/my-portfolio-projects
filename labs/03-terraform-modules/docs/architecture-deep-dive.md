# Lab 03: Production-Grade Terraform Module Library — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework + Infrastructure Engineering Principles  
> **Scope:** 40-module multi-cloud library (AWS 16 · Azure 12 · GCP 12)

---

## What This Library Solves

Every new cloud engagement without a module library starts the same way: copy-paste from a previous project, adjust variable names, forget to enable encryption, miss the NAT Gateway, deploy to production, discover the issue. A module library doesn't just save time — it embeds institutional knowledge about what "correct" looks like and prevents an entire class of security and reliability mistakes from being possible.

The value proposition: **consistency by default, flexibility by exception**.

---

## Module Design Principles

### Principle 1 — Secure by Default

Every module ships with security features enabled. Disabling them requires explicit opt-out.

```hcl
# modules/aws/s3/variables.tf
variable "enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true  # ← on by default
}

variable "block_public_access" {
  description = "Block all public access"
  type        = bool
  default     = true  # ← on by default; must explicitly set false to override
}

variable "enable_encryption" {
  description = "Enable SSE-KMS encryption"
  type        = bool
  default     = true  # ← on by default
}
```

An engineer who creates an S3 bucket without specifying these variables gets versioning, public access blocked, and encryption enabled automatically. The security cost of "I forgot" is eliminated.

### Principle 2 — Consistent Interface

All modules share the same variable names for common concepts:

```hcl
variable "project_name" { ... }  # Used in naming all resources
variable "environment" { ... }   # "dev" | "staging" | "prod"
variable "tags" {
  type    = map(string)
  default = {}
}
```

A developer using both the AWS VPC module and the GCP VPC module uses the same variable names. The cognitive load of learning "what do I call the project name in this module?" is eliminated.

### Principle 3 — Output What Consumers Need

Every module outputs the IDs, ARNs, and attributes that downstream modules need:

```hcl
# modules/vpc/outputs.tf
output "vpc_id"              { value = aws_vpc.main.id }
output "public_subnet_ids"   { value = aws_subnet.public[*].id }
output "private_subnet_ids"  { value = aws_subnet.private[*].id }
output "nat_gateway_ids"     { value = aws_nat_gateway.main[*].id }
```

The EKS module takes `private_subnet_ids` as input. Module composition becomes output-chaining:

```hcl
module "vpc" {
  source = "./modules/vpc"
  # ...
}

module "eks" {
  source             = "./modules/eks"
  private_subnet_ids = module.vpc.private_subnet_ids  # chain outputs
  # ...
}
```

---

## Step-by-Step: AWS Module Design

### Step 1 — VPC Module (Foundation for Everything)

`modules/vpc/main.tf` provisions:

```
VPC (10.0.0.0/16)
├── 3 Public Subnets    (one per AZ): 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24
├── 3 Private Subnets   (one per AZ): 10.0.10.0/24, 10.0.20.0/24, 10.0.30.0/24
├── Internet Gateway    (for public subnets)
├── 3 NAT Gateways      (one per AZ for private subnet egress)
├── Route Tables        (public → IGW, private → NAT)
└── VPC Flow Logs       (to CloudWatch Logs)
```

**Why 3 NAT Gateways not 1?**  
A single NAT Gateway in AZ-a: if AZ-a fails, private subnets in AZ-b and AZ-c lose internet access. ECS tasks cannot pull images from ECR, Lambda cannot call AWS APIs, instances cannot reach Secrets Manager. A NAT Gateway per AZ costs ~$135/month total vs ~$45/month for one — the 3× cost buys AZ-independent egress.

**VPC Flow Logs — why always on?**  
Flow Logs record `srcip, dstip, srcport, dstport, protocol, bytes, packets, start, end, action` for every network flow. Cost: ~$0.50/GB ingested to CloudWatch. Value: security investigations (detect lateral movement), network troubleshooting (confirm traffic is reaching security groups), and compliance (SOC 2 requires network access logs). The module enables them by default with a 30-day retention policy.

**CIDR design — why /24 subnets?**  
A /24 provides 254 usable IPs per subnet. For EKS, each pod gets its own IP from the subnet CIDR (VPC CNI). A /24 supports ~250 pods per subnet × 3 subnets = 750 pods per AZ. For larger clusters, the module accepts an override variable (`subnet_size`) to use /22 (1,022 IPs each).

### Step 2 — EKS Module

`modules/eks/main.tf` provisions:

```hcl
resource "aws_eks_cluster" "main" {
  name    = "${var.project_name}-${var.environment}"
  version = var.kubernetes_version  # default: "1.28"
  
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.enable_public_endpoint  # default: true (restrict to CIDR)
    public_access_cidrs     = var.allowed_cidr_blocks
  }
  
  encryption_config {
    provider { key_arn = aws_kms_key.eks.arn }
    resources = ["secrets"]  # Encrypt K8s secrets in etcd
  }
  
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}
```

**Why encrypt Kubernetes secrets in etcd?**  
Kubernetes Secrets are base64-encoded by default in etcd — not encrypted. An attacker with etcd access (via a compromised control plane) can decode all secrets. KMS encryption of etcd means secrets are encrypted at rest with a customer-managed key. Access to the key is logged in CloudTrail.

**Why enable all control plane log types?**  
Control plane logs are written to CloudWatch at no additional cost beyond CloudWatch storage. They provide:
- `api`: every request to the Kubernetes API server — detect unauthorized API calls
- `audit`: who did what to which resource — SOC 2 audit trail
- `authenticator`: IAM to Kubernetes authentication — debug RBAC issues
- `controllerManager` + `scheduler`: cluster operations — diagnose workload scheduling issues

**OIDC Provider — why always created?**  
The OIDC provider enables IRSA (IAM Roles for Service Accounts). Without it, every pod on a node shares the node's EC2 instance role — the instance role must include every permission any pod on that node needs. This violates least privilege. The OIDC provider is created even if IRSA isn't used immediately because adding it later requires destroying and recreating the cluster.

### Step 3 — S3 Module

```hcl
resource "aws_s3_bucket" "main" {
  bucket = "${var.project_name}-${var.environment}-${var.bucket_suffix}"
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Why SSE-KMS by default (not SSE-S3)?**  
SSE-S3 uses AWS-managed keys — encryption is transparent and cheap but provides no key policy control and no CloudTrail log for individual object decryptions. SSE-KMS uses a KMS key (AWS-managed or CMK) where every `GetObject` call that decrypts data is logged in CloudTrail. For compliance workloads, this audit trail is required. For non-compliance workloads, SSE-KMS is still the right default — the cost overhead is $0.0000004 per API call, negligible.

**Why include a lifecycle policy in the module?**  
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = "Enabled"
      transition {
        days          = rule.value.transition_days
        storage_class = rule.value.storage_class  # "STANDARD_IA", "GLACIER", etc.
      }
    }
  }
}
```
Without lifecycle rules, S3 buckets grow unbounded. The most common bug in S3 usage: a log bucket that ingests 10GB/day, runs for 3 years, accumulates 10TB, and generates $230/month in storage costs when it could be $15/month with Glacier after 90 days. The module prompts for lifecycle configuration by making it a variable.

### Step 4 — DynamoDB Module

```hcl
resource "aws_dynamodb_table" "main" {
  name         = "${var.project_name}-${var.environment}-${var.table_name}"
  billing_mode = var.billing_mode  # "PAY_PER_REQUEST" or "PROVISIONED"
  
  hash_key  = var.partition_key
  range_key = var.sort_key != "" ? var.sort_key : null
  
  point_in_time_recovery {
    enabled = true  # always on — enables 35-day PITR window
  }
  
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }
  
  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
    }
  }
  
  ttl {
    attribute_name = var.ttl_attribute
    enabled        = var.ttl_attribute != "" ? true : false
  }
}
```

**Why PITR always on?**  
Point-in-Time Recovery provides a 35-day rolling backup window. Cost: 0.2 cents per GB per month. The cost of enabling PITR is negligible; the cost of not having it when a developer deletes a table or runs a bad scan-delete is potentially irreversible data loss.

**Why PAY_PER_REQUEST as the default billing mode?**  
PAY_PER_REQUEST charges $1.25/million write request units and $0.25/million read request units. For variable or unpredictable traffic, this is always correct — there's no idle cost. PROVISIONED mode requires capacity planning: guess too low and throttling occurs; guess too high and you pay for unused capacity. PAY_PER_REQUEST is the correct default; switch to PROVISIONED only when cost analysis shows predictable high throughput.

---

## Step-by-Step: GCP Module Design

### Step 5 — GKE Module with Workload Identity

```hcl
resource "google_container_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  location = var.region
  
  # Regional cluster (not zonal) for HA
  node_locations = var.node_zones  # ["us-central1-a", "us-central1-b", "us-central1-c"]
  
  private_cluster_config {
    enable_private_nodes    = true  # nodes have no public IPs
    enable_private_endpoint = false # API server accessible via public endpoint (with authorized networks)
    master_ipv4_cidr_block  = "172.16.0.0/28"  # control plane CIDR
  }
  
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"  # enables Workload Identity
  }
  
  release_channel {
    channel = "REGULAR"  # Not RAPID (too experimental) or STABLE (too old)
  }
}
```

**Why regional cluster (not zonal)?**  
A zonal cluster has a single-zone control plane. If that zone fails, the control plane becomes unavailable — new pods cannot be scheduled, Kubernetes API calls fail. A regional cluster replicates the control plane across 3 zones. Worker nodes can still process existing requests even if the control plane is briefly unavailable, but the regional control plane provides a much stronger availability guarantee.

**Why `REGULAR` release channel?**  
- `RAPID`: Latest K8s versions, least tested, potential breaking changes
- `REGULAR`: 2–3 months behind RAPID, tested by Google before promotion, security patches included
- `STABLE`: Oldest supported version, fewest bugs but delayed security patches

`REGULAR` balances stability with timely security updates.

**Workload Identity — why over service account key files?**  
GCP service account key files are long-lived credentials that must be rotated, stored securely, and distributed to each pod that needs them. A leaked key file is an open door. Workload Identity binds a Kubernetes ServiceAccount to a GCP Service Account via the OIDC federation — pods authenticate with their Kubernetes identity and receive short-lived GCP credentials automatically. No key files to manage, no rotation, no leakage risk.

---

## Module Composition: Full Environment Example

```hcl
# examples/aws-complete/main.tf

module "vpc" {
  source       = "../../modules/vpc"
  project_name = var.project_name
  environment  = var.environment
  cidr_block   = "10.0.0.0/16"
  azs          = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

module "eks" {
  source             = "../../modules/eks"
  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.vpc.private_subnet_ids  # output → input
  vpc_id             = module.vpc.vpc_id
}

module "rds" {
  source             = "../../modules/rds"
  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.vpc.private_subnet_ids  # same VPC subnets
  vpc_id             = module.vpc.vpc_id
  database_name      = "app"
}

module "alb" {
  source            = "../../modules/aws/alb"
  project_name      = var.project_name
  environment       = var.environment
  public_subnet_ids = module.vpc.public_subnet_ids  # ALB in public subnets
  vpc_id            = module.vpc.vpc_id
}
```

**Why Terratest for infrastructure testing?**

```go
func TestEKSModule(t *testing.T) {
    options := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../../modules/eks",
        Vars: map[string]interface{}{
            "project_name": "test",
            "environment":  "test",
        },
    })
    defer terraform.Destroy(t, options)
    
    terraform.InitAndApply(t, options)
    
    clusterName := terraform.Output(t, options, "cluster_name")
    assert.NotEmpty(t, clusterName)
    
    // Verify the cluster is ACTIVE
    client := aws.NewEksClient(t, "us-east-1")
    cluster := aws.GetEksCluster(t, "us-east-1", clusterName)
    assert.Equal(t, "ACTIVE", aws.GetClusterStatus(t, client, clusterName))
}
```

Terraform `validate` and `plan` catch syntax errors and some logical errors. They do not test: whether the IAM policy actually allows what it claims, whether the security group rules actually permit the required traffic, or whether the EKS cluster actually starts successfully. Terratest deploys real infrastructure in a throwaway AWS account, runs assertions against it, and tears it down. The test catches: IAM permission gaps, misconfigured security groups, and invalid Kubernetes versions — none of which `terraform plan` would catch.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Version-controlled modules:** All modules in Git — every change is reviewable, reversible, and auditable
- **Consistent naming:** `${project_name}-${environment}-resource` naming convention applied uniformly — CloudWatch filters, cost tags, and IAM policies can target by pattern
- **Module composition:** Full environments provisioned from `terraform apply` in a single command — no manual steps

### Security
- **Encryption by default:** Every storage module (S3, DynamoDB, EBS, RDS, GCS) enables encryption in the default configuration
- **Public access blocked by default:** S3, ECR, and GCS modules block public access unless explicitly opted out
- **Least-privilege module IAM roles:** Each module creates only the IAM roles its resources require

### Reliability
- **Multi-AZ by default:** VPC module creates subnets in 3 AZs; RDS module creates Multi-AZ instances
- **PITR always enabled:** DynamoDB and Aurora PITR enabled by default — 35-day recovery window
- **Lifecycle policies:** S3, ECR, and GCS modules include lifecycle policies — resources don't silently grow to failure

### Performance Efficiency
- **Right-sized defaults:** Module defaults target the most common workload. Large workloads override via variables — no need to understand the module internals
- **arm64 support:** Lambda and ECS Fargate modules support `arm64` architecture variable — 20% cost reduction, better performance

### Cost Optimization
- **PAY_PER_REQUEST defaults:** DynamoDB and Pub/Sub modules default to on-demand billing — no idle capacity cost
- **Lifecycle rules:** S3 lifecycle rules in the module prevent storage cost explosions
- **Module reuse:** 10+ client engagements using the same modules vs. custom implementation per client — engineering hours saved, billing errors avoided

### Sustainability
- **Graviton-default Fargate/Lambda:** arm64 architecture uses less energy per compute unit
- **Lifecycle rules prevent waste:** Automated data tiering moves cold data to energy-efficient archival storage

---

## Key Architectural Insight

A Terraform module is not just reusable code — it is an **opinionated encoding of architectural decisions**. The `enable_encryption = true` default in the S3 module is not a preference; it's a statement that unencrypted S3 buckets are wrong in all contexts we build for. The PITR default in the DynamoDB module is a statement that unrecoverable data loss is unacceptable. When these decisions are in modules rather than in individual project Terraform files, they apply automatically to every future consumer — including engineers who have never thought about encryption or backup strategy. That is the compounding return of a module library.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
