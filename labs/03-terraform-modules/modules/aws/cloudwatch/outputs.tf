# ============================================================
# CloudWatch Module — Outputs
# Author: Jenella Awo
# ============================================================

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.this.name
}

output "alarm_arns" {
  description = "Map of alarm names to their ARNs"
  value       = { for k, v in aws_cloudwatch_metric_alarm.this : k => v.arn }
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard (null if no widgets configured)"
  value       = length(var.dashboard_widgets) > 0 ? aws_cloudwatch_dashboard.this[0].dashboard_arn : null
}
