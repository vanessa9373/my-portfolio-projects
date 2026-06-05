# Lab 15: Cloud Security & Compliance Framework — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + AWS Security Hub FSBP + ISO 27001 + SOC 2  
> **Scope:** Security Hub + GuardDuty + AWS Config (15 rules) + CloudTrail + KMS + WAF — full Terraform IaC

---

## What This Framework Solves

Security configurations that are set once and never validated gradually drift from their intended state. An S3 bucket that was private when created can be made public by an IAM user who doesn't understand the implications. An EBS volume attached to a new instance might not have encryption enabled if encryption-by-default was never configured. Manual security reviews catch these issues quarterly — automated continuous compliance evaluation catches them within minutes. This lab implements the AWS security services that provide continuous, automatic evaluation.

---

## Architecture: Defense in Depth (Four Detection Layers)

```
AWS Security Stack
         │
         ├── Layer 1: Real-time threat detection
         │     └── GuardDuty (ML-based anomaly detection)
         │           ├── Unusual API calls (CloudTrail analysis)
         │           ├── Suspicious network activity (VPC Flow Logs analysis)
         │           └── Compromised EC2/EKS instances (DNS + network patterns)
         │
         ├── Layer 2: Continuous compliance evaluation
         │     └── AWS Config (15 managed rules, evaluated continuously)
         │           ├── encrypted-volumes: EBS volumes must be encrypted
         │           ├── s3-bucket-public-read-prohibited: no public S3
         │           ├── mfa-enabled-for-iam-console-access: MFA required
         │           ├── access-keys-rotated: keys expire after 90 days
         │           └── [11 more rules covering EC2, RDS, Lambda, CloudTrail]
         │
         ├── Layer 3: Centralized findings aggregation
         │     └── Security Hub
         │           ├── Aggregates from GuardDuty, Config, Inspector, Macie
         │           ├── Normalizes to ASFF (Amazon Security Finding Format)
         │           └── Enables FSBP (Foundational Security Best Practices) standard
         │
         └── Layer 4: Audit trail
               └── CloudTrail (multi-region, S3 with Object Lock)
                     └── Every API call logged, tamper-proof, 1-year retention
```

---

## Step-by-Step: Security Framework Deployment

### Step 1 — Security Hub and GuardDuty Activation

```hcl
# terraform/main.tf
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "fsbp" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/1.2.0"
}

resource "aws_guardduty_detector" "main" {
  enable = true
  
  datasources {
    s3_logs {
      enable = true  # detect malicious S3 access patterns
    }
    kubernetes {
      audit_logs {
        enable = true  # detect unusual EKS API calls
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true  # scan EBS for malware on GuardDuty findings
        }
      }
    }
  }
  
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}
```

**Why enable Security Hub before GuardDuty findings are configured?**  
Security Hub aggregates findings from GuardDuty, AWS Config, Inspector, and Macie. If GuardDuty is enabled before Security Hub, findings from GuardDuty's first days of operation are not automatically integrated into the Security Hub aggregated view — they must be manually imported. Enabling Security Hub first ensures that all findings from day one flow into the central dashboard.

**Why enable S3 and Kubernetes audit logs in GuardDuty?**  
GuardDuty's baseline anomaly detection analyzes CloudTrail events and VPC Flow Logs. S3 protection additionally analyzes S3 data plane events (GetObject, PutObject) to detect data exfiltration patterns — a compromised credential used to download all objects from a sensitive S3 bucket would be flagged. Kubernetes audit log analysis detects unusual EKS API calls that might indicate a compromised pod attempting to escalate privileges or access secrets.

### Step 2 — AWS Config Compliance Rules

```hcl
# terraform/main.tf (Config rules)
resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config.arn
  
  recording_group {
    all_supported = true   # record all resource types
    include_global_resource_types = true  # includes IAM
  }
}

locals {
  config_rules = [
    "encrypted-volumes",
    "s3-bucket-public-read-prohibited",
    "s3-bucket-public-write-prohibited",
    "mfa-enabled-for-iam-console-access",
    "access-keys-rotated",
    "iam-root-access-key-check",
    "root-account-mfa-enabled",
    "cloudtrail-enabled",
    "cloudtrail-encryption-enabled",
    "vpc-default-security-group-closed",
    "restricted-ssh",
    "rds-instance-public-access-check",
    "rds-storage-encrypted",
    "lambda-function-public-access-prohibited",
    "guardduty-enabled-centralized",
  ]
}

resource "aws_config_managed_rule" "rules" {
  for_each    = toset(local.config_rules)
  name        = each.value
  source {
    owner             = "AWS"
    source_identifier = upper(replace(each.value, "-", "_"))
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}
```

**Why managed rules rather than custom rules?**  
AWS managed rules are maintained by AWS, updated when services change their APIs, and pre-approved for common compliance frameworks (SOC 2, PCI DSS, ISO 27001). A custom rule that checks "is the EBS volume encrypted?" requires maintenance every time AWS changes the EBS API or adds new volume types. Managed rules handle API evolution automatically. Custom rules are appropriate for business-specific checks (e.g., "all resources must have a cost-center tag") that AWS cannot provide generically.

**Why `all_supported: true` in the recording group?**  
Config rules can only evaluate resources that Config has recorded. A rule checking RDS encryption cannot evaluate RDS instances if Config is not recording RDS resources. Enabling all resource types ensures no new AWS service type is introduced without Config recording coverage — a new service type can be evaluated against security rules immediately without updating the Terraform configuration.

### Step 3 — KMS Encryption for All Data Stores

```hcl
resource "aws_kms_key" "main" {
  description             = "CMK for S3, EBS, RDS encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true  # rotate annually
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudTrailEncryption"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ebs_encryption_by_default" "main" {
  enabled = true  # all new EBS volumes encrypted with CMK automatically
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true  # reduces KMS API calls by 99% for S3
  }
}
```

**Why customer-managed keys (CMK) rather than AWS-managed keys (SSE-S3 or `aws/s3`)?**  
AWS-managed keys cannot have key policies attached — you cannot grant or restrict which IAM principals can decrypt data. CMKs have explicit key policies that define exactly who can use the key for encryption and decryption. For a compliance audit, the key policy is evidence that only authorized principals can access sensitive data. SSE-S3 provides encryption at rest but not access control over who can decrypt.

**Why `bucket_key_enabled: true` on S3?**  
By default, every S3 object GET with SSE-KMS generates a KMS API call to decrypt the data key. At 1 million S3 reads/day, that's 1 million KMS API calls/day. S3 Bucket Keys generate a short-lived envelope key at the bucket level — individual object reads don't call KMS. This reduces KMS API calls by 99% and eliminates the per-request cost at scale.

**Why `enable_key_rotation: true`?**  
Key rotation limits the exposure if a key is compromised. A key rotated annually means a compromised key can decrypt at most one year of data. Without rotation, a key compromised today could decrypt all data back to key creation. Most compliance standards (SOC 2, ISO 27001) require cryptographic key rotation and use key rotation configuration as audit evidence.

### Step 4 — CloudTrail Configuration

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "security-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true   # captures IAM events in all regions
  is_multi_region_trail         = true   # single trail covers all regions
  enable_log_file_validation    = true   # detects if log files are tampered with
  
  kms_key_id = aws_kms_key.main.arn
  
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::sensitive-data-bucket/"]
    }
  }
}

resource "aws_s3_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  
  rule {
    default_retention {
      mode  = "GOVERNANCE"
      years = 1
    }
  }
}
```

**Why multi-region trail rather than per-region trails?**  
IAM events (CreateUser, AttachPolicy, etc.) are global events that only appear in us-east-1 CloudTrail by default. A per-region trail in eu-west-1 would miss IAM changes. A multi-region trail with `include_global_service_events: true` captures all events — region-local and global — in a single, consistent log stream. This is the configuration required by CIS Benchmark control 2.1.

**Why Object Lock (WORM) on the CloudTrail S3 bucket?**  
CloudTrail logs are the authoritative audit record of who did what and when. Without Object Lock, a compromised administrative credential could delete CloudTrail logs, eliminating evidence of the breach. Object Lock in GOVERNANCE mode prevents deletion or modification for the retention period — even by users with `s3:DeleteObject` permission. For compliance audits, immutable logs are required evidence.

### Step 5 — Security Audit Script

```bash
#!/bin/bash
# scripts/security-audit.sh

echo "=== Security Audit Report ==="
echo "Date: $(date)"
echo

echo "1. Checking for public S3 buckets..."
aws s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n' | while read bucket; do
    public=$(aws s3api get-bucket-policy-status --bucket "$bucket" --query 'PolicyStatus.IsPublic' 2>/dev/null)
    if [ "$public" = "true" ]; then
        echo "  FAIL: $bucket is PUBLIC"
    fi
done

echo "2. Checking for unencrypted EBS volumes..."
aws ec2 describe-volumes \
    --query 'Volumes[?Encrypted==`false`].[VolumeId,State]' \
    --output table

echo "3. Checking IAM users without MFA..."
aws iam list-users --query 'Users[].UserName' --output text | tr '\t' '\n' | while read user; do
    mfa=$(aws iam list-mfa-devices --user-name "$user" --query 'MFADevices | length(@)')
    if [ "$mfa" = "0" ]; then
        echo "  FAIL: $user has no MFA device"
    fi
done

echo "4. Checking access keys older than 90 days..."
aws iam generate-credential-report && sleep 5
aws iam get-credential-report --query 'Content' --output text | base64 -d | \
    awk -F',' 'NR>1 && $9!="N/A" && ($9 < strftime("%Y-%m-%dT%H:%M:%S", systime()-90*86400)) {print "  WARN:", $1, "key age:", $9}'
```

**Why a shell script audit in addition to AWS Config continuous evaluation?**  
AWS Config evaluates resources continuously but the results are distributed across the Config console, Security Hub, and individual rule pages. The shell script produces a single consolidated report that can be emailed to stakeholders, included in audit documentation, or run as a pre-audit checklist. It also covers items (like access key age relative to today's date) that are easier to express in shell arithmetic than in Config rule expressions.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **100% postmortem completion:** Every compliance violation produces a finding in Security Hub with severity, affected resource, and recommended remediation steps — no investigation needed to understand what failed and how to fix it
- **Automated weekly audit reports:** Security audit script runs on schedule; stakeholders receive compliance status without manual review

### Security
- **Defense in depth:** GuardDuty (threats), Config (configuration drift), Security Hub (aggregation), CloudTrail (audit trail) — each layer catches different failure modes
- **CMK encryption with rotation:** Key policies control who can decrypt; annual rotation limits exposure window
- **CloudTrail + Object Lock:** Immutable audit logs cannot be deleted even by compromised privileged accounts

### Reliability
- **Continuous Config evaluation:** Compliance violations are detected within minutes of occurrence, not at the next quarterly review
- **GuardDuty ML-based detection:** Detects novel threats (unusual API call sequences) that signature-based detection would miss

### Performance Efficiency
- **S3 Bucket Keys:** Reduce KMS API calls by 99% for encrypted S3 data — eliminates per-request KMS throttling at scale
- **Security Hub normalized format (ASFF):** Single aggregated view eliminates the need to check five separate security dashboards

### Cost Optimization
- **Managed Config rules:** Zero maintenance cost vs custom rules; AWS handles rule updates when AWS APIs change
- **Single multi-region CloudTrail:** One trail costs the same as multiple single-region trails but provides complete global coverage

### Sustainability
- **Automated compliance prevents remediation spikes:** Continuous evaluation catches violations early, when they require a single resource configuration change; compliance that drifts unchecked for a year requires a coordinated remediation project

---

## Key Architectural Insight

The most important property of this security framework is that it is **self-auditing** — it doesn't rely on scheduled human review to detect problems. AWS Config evaluates resources continuously. GuardDuty analyzes API calls and network traffic in real time. Security Hub aggregates findings immediately. This creates a security posture where the elapsed time between a misconfiguration and its detection is measured in minutes, not months. The healthcare client's ISO 27001 audit passed not because the auditors found nothing wrong, but because the security framework was continuously ensuring there was nothing to find.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
