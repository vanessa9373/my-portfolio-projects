# ============================================================
# ECR Module — Container Registry with Image Scanning,
# Encryption, Lifecycle Policies, and Cross-Account Access
# Author: Jenella Awo
# ============================================================

locals {
  repository_name = "${var.project_name}-${var.repository_name}"
}

# ----------------------------------------------
# ECR Repository
# ----------------------------------------------
resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key         = var.encryption_type == "KMS" ? var.kms_key_arn : null
  }

  tags = merge(var.tags, {
    Name = local.repository_name
  })
}

# ----------------------------------------------
# Lifecycle Policy
# ----------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest", "release", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ----------------------------------------------
# Repository Policy for Cross-Account Access
# ----------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository_policy" "cross_account" {
  count      = length(var.cross_account_arns) > 0 ? 1 : 0
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCrossAccountPull"
        Effect    = "Allow"
        Principal = { AWS = var.cross_account_arns }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      },
      {
        Sid       = "AllowSameAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "ecr:*"
      }
    ]
  })
}
