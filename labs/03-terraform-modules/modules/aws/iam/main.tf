# ============================================================
# IAM Module — Reusable IAM Roles, Policies, Instance Profiles,
# and OIDC-Based Roles for EKS IRSA
# Author: Jenella Awo
# ============================================================

locals {
  role_name = "${var.project_name}-${var.role_name}"

  # Build assume role policy for service principals
  service_assume_role_policy = length(var.service_principals) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = var.service_principals }
        Action    = "sts:AssumeRole"
      }
    ]
  }) : null

  # Build assume role policy for OIDC (EKS IRSA)
  oidc_assume_role_policy = var.oidc_provider_arn != null ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = var.oidc_conditions
        }
      }
    ]
  }) : null

  # Use OIDC policy if provided, otherwise service principal policy
  assume_role_policy = local.oidc_assume_role_policy != null ? local.oidc_assume_role_policy : local.service_assume_role_policy
}

# ----------------------------------------------
# IAM Role
# ----------------------------------------------
resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = local.assume_role_policy
  path               = "/"

  tags = merge(var.tags, {
    Name = local.role_name
  })
}

# ----------------------------------------------
# Managed Policy Attachments
# ----------------------------------------------
resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = toset(var.managed_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# ----------------------------------------------
# Inline Policy (optional)
# ----------------------------------------------
resource "aws_iam_role_policy" "inline" {
  count  = var.inline_policy_json != null ? 1 : 0
  name   = "${local.role_name}-inline-policy"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}

# ----------------------------------------------
# Instance Profile (optional)
# ----------------------------------------------
resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0
  name  = "${local.role_name}-instance-profile"
  role  = aws_iam_role.this.name

  tags = merge(var.tags, {
    Name = "${local.role_name}-instance-profile"
  })
}
