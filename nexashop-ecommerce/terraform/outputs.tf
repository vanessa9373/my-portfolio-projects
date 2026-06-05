output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = module.cdn.cloudfront_domain
}

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = module.ecs.api_gateway_url
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.ecs.alb_dns_name
}

output "aurora_cluster_endpoint" {
  description = "Aurora writer endpoint"
  value       = module.rds.cluster_endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint (for read replicas)"
  value       = module.rds.reader_endpoint
  sensitive   = true
}

output "dynamodb_products_table" {
  description = "DynamoDB products table name"
  value       = aws_dynamodb_table.products.name
}

output "orders_queue_url" {
  description = "SQS orders queue URL"
  value       = aws_sqs_queue.orders.url
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  description = "Cognito app client ID"
  value       = module.cognito.app_client_id
}

output "kms_key_arn" {
  description = "NexaShop KMS key ARN"
  value       = aws_kms_key.nexashop.arn
}

output "frontend_bucket_name" {
  description = "S3 bucket for React frontend assets"
  value       = module.cdn.frontend_bucket_name
}
