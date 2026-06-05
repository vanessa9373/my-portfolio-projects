locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── S3 BUCKET FOR MEDIA + STATIC ASSETS ─────────────────────────────────────

resource "aws_s3_bucket" "media" {
  bucket = "${local.name_prefix}-media-${var.account_id}"

  tags = { Name = "${local.name_prefix}-media" }
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true  # Reduces KMS API calls by ~99%, saves cost
  }
}

# Block all public access — objects served via CloudFront only
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle — move old versions to cheaper storage
resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "media-lifecycle"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ─── CLOUDFRONT OAC ───────────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${local.name_prefix}-s3-oac"
  description                       = "OAC for ${local.name_prefix} S3 media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Bucket policy — only CloudFront can access via OAC
resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.media.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}

# ─── CLOUDFRONT DISTRIBUTION ──────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} WordPress CDN"
  default_root_object = "index.php"
  aliases             = var.domain_name != "" ? [var.domain_name, "www.${var.domain_name}"] : []
  web_acl_id          = var.waf_acl_arn
  price_class         = "PriceClass_100"  # US, Canada, Europe — cheapest

  # Origin 1: ALB (WordPress dynamic content)
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # CloudFront → ALB origin timeout
      origin_read_timeout      = 60
      origin_keepalive_timeout = 60
    }

    custom_header {
      name  = "X-CloudFront-Secret"
      value = var.cloudfront_header_secret
    }
  }

  # Origin 2: S3 media bucket (static files)
  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "s3-media"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Default behavior: route to WordPress ALB
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # Don't cache dynamic WordPress pages
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"  # AllViewer

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # Cache behavior: WordPress media uploads (S3)
  ordered_cache_behavior {
    path_pattern           = "/wp-content/uploads/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-media"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"  # CachingOptimized

    min_ttl     = 0
    default_ttl = 86400     # 1 day
    max_ttl     = 31536000  # 1 year
  }

  # Cache behavior: WordPress static assets (themes, plugins)
  ordered_cache_behavior {
    path_pattern           = "/wp-content/themes/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"  # CachingOptimized

    min_ttl     = 0
    default_ttl = 3600      # 1 hour
    max_ttl     = 86400     # 1 day
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket          = aws_s3_bucket.cf_logs.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  tags = { Name = "${local.name_prefix}-cloudfront" }
}

# CloudFront access logs bucket
resource "aws_s3_bucket" "cf_logs" {
  bucket        = "${local.name_prefix}-cf-logs-${var.account_id}"
  force_destroy = true

  tags = { Name = "${local.name_prefix}-cf-logs" }
}

resource "aws_s3_bucket_ownership_controls" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

# ─── ROUTE 53 ─────────────────────────────────────────────────────────────────

data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "apex" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
