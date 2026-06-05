# ============================================================
# Lambda Module — Outputs
# Author: Jenella Awo
# ============================================================

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.this.invoke_arn
}

output "function_url" {
  description = "The function URL (null if not enabled)"
  value       = var.enable_function_url ? aws_lambda_function_url.this[0].function_url : null
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda.arn
}
