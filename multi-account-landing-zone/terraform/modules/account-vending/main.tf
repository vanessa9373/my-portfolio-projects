"""
Account Vending Machine — provisions new AWS accounts under an OU with baseline guardrails.

Usage:
  module "dev_account" {
    source      = "./modules/account-vending"
    account_name = "nexacorp-dev-payments"
    email        = "aws+dev-payments@company.com"
    parent_ou_id = "ou-xxxx-dev"
    environment  = "dev"
  }
"""

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# Create account under Organizations
resource "aws_organizations_account" "this" {
  name                       = var.account_name
  email                      = var.email
  parent_id                  = var.parent_ou_id
  iam_user_access_to_billing = "ALLOW"

  tags = {
    AccountName = var.account_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  lifecycle {
    # AWS accounts cannot be deleted via API — prevent accidental destroy
    prevent_destroy = true
    ignore_changes  = [email]  # Email changes require support ticket
  }
}

# Enable CloudTrail in the new account via delegation
resource "aws_cloudtrail" "org_trail_subscription" {
  provider = aws.child_account

  name                          = "org-trail"
  s3_bucket_name                = var.cloudtrail_bucket_name
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = { ManagedBy = "Terraform" }
}

# Baseline SCPs attached to the account's OU (inherited)
# SCPs are managed in the root module — this module just documents which apply
output "applied_scps" {
  value = [
    "DenyRootUserActions",
    "DenyLeaveOrganization",
    "RequireIMDSv2",
    "DenyPublicS3Buckets",
    "RequireEncryptionAtRest",
    "DenyUnauthorizedRegions",
  ]
}
