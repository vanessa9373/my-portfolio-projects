"""
Service Control Policies (SCPs) — organization-wide guardrails.
Applied to OUs, inherited by all accounts in the OU.
These cannot be bypassed even by account root users.
"""

# ─── SCP 1: Deny root user actions ───────────────────────────────────────────

resource "aws_organizations_policy" "deny_root" {
  name        = "DenyRootUserActions"
  description = "Prevent root user from performing any API actions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyRootUser"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = ["arn:aws:iam::*:root"]
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_root" {
  policy_id = aws_organizations_policy.deny_root.id
  target_id = aws_organizations_organization.main.roots[0].id  # Apply to root = all accounts
}

# ─── SCP 2: Prevent leaving the organization ──────────────────────────────────

resource "aws_organizations_policy" "deny_leave_org" {
  name        = "DenyLeaveOrganization"
  description = "Prevent accounts from leaving the organization"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyLeaveOrg"
      Effect   = "Deny"
      Action   = ["organizations:LeaveOrganization"]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_leave_org" {
  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = aws_organizations_organization.main.roots[0].id
}

# ─── SCP 3: Require IMDSv2 on all EC2 instances ───────────────────────────────

resource "aws_organizations_policy" "require_imdsv2" {
  name        = "RequireIMDSv2"
  description = "Deny launching EC2 instances that allow IMDSv1 (SSRF protection)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyIMDSv1"
      Effect = "Deny"
      Action = ["ec2:RunInstances"]
      Resource = "arn:aws:ec2:*:*:instance/*"
      Condition = {
        StringNotEquals = {
          "ec2:MetadataHttpTokens" = "required"
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "require_imdsv2" {
  policy_id = aws_organizations_policy.require_imdsv2.id
  target_id = var.workloads_ou_id
}

# ─── SCP 4: Deny disabling CloudTrail ────────────────────────────────────────

resource "aws_organizations_policy" "protect_cloudtrail" {
  name        = "ProtectCloudTrail"
  description = "Prevent anyone from disabling or modifying org CloudTrail"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyCloudTrailModification"
      Effect = "Deny"
      Action = [
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "cloudtrail:UpdateTrail",
        "cloudtrail:PutEventSelectors",
      ]
      Resource = "*"
      Condition = {
        StringNotLike = {
          "aws:PrincipalArn" = [
            "arn:aws:iam::*:role/OrganizationAccountAccessRole",
            "arn:aws:iam::*:role/AWSControlTowerExecution",
          ]
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "protect_cloudtrail" {
  policy_id = aws_organizations_policy.protect_cloudtrail.id
  target_id = aws_organizations_organization.main.roots[0].id
}

# ─── SCP 5: Restrict to approved regions ─────────────────────────────────────

resource "aws_organizations_policy" "allowed_regions" {
  name        = "AllowedRegionsOnly"
  description = "Restrict workloads to us-east-1 and us-west-2. Allows global services."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyUnapprovedRegions"
      Effect = "Deny"
      NotAction = [
        "iam:*", "organizations:*", "support:*", "budgets:*",
        "cloudfront:*", "route53:*", "sts:*", "waf:*",
        "acm:RequestCertificate", "acm:DescribeCertificate",
        "acm:ListCertificates", "acm:DeleteCertificate",
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = ["us-east-1", "us-west-2"]
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "allowed_regions" {
  policy_id = aws_organizations_policy.allowed_regions.id
  target_id = var.workloads_ou_id
}

# ─── SCP 6: Deny public S3 buckets ───────────────────────────────────────────

resource "aws_organizations_policy" "deny_public_s3" {
  name        = "DenyPublicS3Buckets"
  description = "Prevent disabling S3 Block Public Access settings"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicS3ACLs"
        Effect = "Deny"
        Action = [
          "s3:PutBucketAcl",
          "s3:PutObjectAcl",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = ["public-read", "public-read-write", "authenticated-read"]
          }
        }
      },
      {
        Sid    = "DenyDisablingBlockPublicAccess"
        Effect = "Deny"
        Action = ["s3:PutBucketPublicAccessBlock"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:PublicAccessBlockConfiguration/BlockPublicAcls"       = "false"
            "s3:PublicAccessBlockConfiguration/BlockPublicPolicy"     = "false"
            "s3:PublicAccessBlockConfiguration/IgnorePublicAcls"      = "false"
            "s3:PublicAccessBlockConfiguration/RestrictPublicBuckets" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_public_s3" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = aws_organizations_organization.main.roots[0].id
}
