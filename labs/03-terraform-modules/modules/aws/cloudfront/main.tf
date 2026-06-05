# ============================================================
# CloudFront Module — Distribution with OAC, Custom Domain,
# Caching Policies, WAF, Geo Restriction, and SPA Support
# Author: Jenella Awo
# ============================================================

locals {
  origin_id  = "${var.project_name}-origin"
  is_s3      = var.origin_type == "s3"
}

# ----------------------------------------------
# Origin Access Control (for S3 origins)
# ----------------------------------------------
resource "aws_cloudfront_origin_access_control" "this" {
  count                             = local.is_s3 ? 1 : 0
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.project_name} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ----------------------------------------------
# CloudFront Distribution
# ----------------------------------------------
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} distribution"
  default_root_object = var.default_root_object
  aliases             = var.domain_aliases
  web_acl_id          = var.waf_web_acl_id
  price_class         = "PriceClass_100"

  # Origin configuration
  origin {
    domain_name              = var.origin_domain_name
    origin_id                = local.origin_id
    origin_access_control_id = local.is_s3 ? aws_cloudfront_origin_access_control.this[0].id : null

    dynamic "custom_origin_config" {
      for_each = local.is_s3 ? [] : [1]
      content {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
    origin_request_policy_id = local.is_s3 ? null : "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  }

  # Custom error responses for SPA routing
  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  # Geo restriction
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.restriction_type
      locations        = var.geo_restriction.locations
    }
  }

  # TLS certificate
  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != null ? "TLSv1.2_2021" : "TLSv1"
    cloudfront_default_certificate = var.acm_certificate_arn == null ? true : false
  }

  # Access logging
  dynamic "logging_config" {
    for_each = var.logging_bucket != null ? [1] : []
    content {
      bucket          = var.logging_bucket
      include_cookies = false
      prefix          = "cloudfront/${var.project_name}/"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-distribution"
  })
}

# ----------------------------------------------
# S3 Bucket Policy for CloudFront OAC
# ----------------------------------------------
data "aws_iam_policy_document" "s3_cloudfront" {
  count = local.is_s3 ? 1 : 0

  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}
