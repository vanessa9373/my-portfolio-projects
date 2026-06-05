output "cloudfront_domain" {
  description = "CloudFront distribution domain — use this as your primary URL"
  value       = module.cdn.cloudfront_domain_name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS (direct access, bypass CloudFront)"
  value       = module.compute.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS writer endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.compute.asg_name
}

output "s3_media_bucket" {
  description = "S3 bucket for WordPress media uploads"
  value       = module.cdn.s3_bucket_name
}

output "waf_acl_id" {
  description = "WAF WebACL ID"
  value       = module.security.waf_acl_id
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for database credentials"
  value       = module.database.db_secret_arn
  sensitive   = true
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.monitoring.dashboard_url
}
