# ============================================================
# DynamoDB Module — Outputs
# Author: Jenella Awo
# ============================================================

output "table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.this.id
}

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.this.arn
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "stream_arn" {
  description = "ARN of the DynamoDB table stream (null if streams are disabled)"
  value       = aws_dynamodb_table.this.stream_arn
}
