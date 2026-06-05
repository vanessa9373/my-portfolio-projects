# ============================================================
# S3 Module — Production S3 Bucket with Encryption, Versioning,
# Lifecycle Rules, Public Access Block, and SSL Enforcement
# Author: Jenella Awo
# ============================================================

data "aws_caller_identity" "current" {}

# ----------------------------------------------
# S3 Bucket
# ----------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket        = "${var.project_name}-${var.bucket_name}"
  force_destroy = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.bucket_name}"
  })
}

# ----------------------------------------------
# Versioning
# ----------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# ----------------------------------------------
# Server-Side Encryption
# ----------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null ? true : false
  }
}

# ----------------------------------------------
# Public Access Block (all four settings)
# ----------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------
# Lifecycle Rules
# ----------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "default-lifecycle"
    status = "Enabled"

    transition {
      days          = var.lifecycle_rules.transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_rules.transition_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.lifecycle_rules.expiration_days
    }

    noncurrent_version_transition {
      noncurrent_days = var.lifecycle_rules.transition_ia_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_rules.expiration_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# ----------------------------------------------
# Bucket Policy — Enforce SSL / TLS
# ----------------------------------------------
resource "aws_s3_bucket_policy" "ssl_enforcement" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSLOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ----------------------------------------------
# CORS Configuration (optional)
# ----------------------------------------------
resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# ----------------------------------------------
# Logging
# ----------------------------------------------
resource "aws_s3_bucket_logging" "this" {
  count  = var.logging_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_bucket
  target_prefix = "s3-logs/${var.project_name}-${var.bucket_name}/"
}

# ----------------------------------------------
# Replication Configuration (optional)
# ----------------------------------------------
resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${var.project_name}-${var.bucket_name}-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.bucket_name}-replication-role"
  })
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_replication ? 1 : 0
  name  = "${var.project_name}-${var.bucket_name}-replication-policy"
  role  = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.this.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.this.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${var.replication_dest_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count  = var.enable_replication ? 1 : 0
  bucket = aws_s3_bucket.this.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = var.replication_dest_bucket_arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
