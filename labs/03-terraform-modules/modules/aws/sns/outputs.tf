# ============================================================
# SNS Module — Outputs
# Author: Jenella Awo
# ============================================================

output "topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.this.arn
}

output "topic_id" {
  description = "ID of the SNS topic"
  value       = aws_sns_topic.this.id
}

output "subscription_arns" {
  description = "Map of subscription ARNs"
  value       = { for k, v in aws_sns_topic_subscription.this : k => v.arn }
}
