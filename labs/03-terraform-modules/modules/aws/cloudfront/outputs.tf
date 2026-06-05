# ============================================================
# CloudFront Module — Outputs
# Author: Jenella Awo
# ============================================================

output "distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "oac_id" {
  description = "ID of the Origin Access Control (null if origin_type is not s3)"
  value       = var.origin_type == "s3" ? aws_cloudfront_origin_access_control.this[0].id : null
}
