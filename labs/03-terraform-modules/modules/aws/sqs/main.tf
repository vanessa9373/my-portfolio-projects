# ============================================================
# SQS Module — Standard/FIFO Queue with Dead-Letter Queue,
# Encryption, Redrive Policy, and Access Policy
# Author: Jenella Awo
# ============================================================

locals {
  queue_name     = var.fifo_queue ? "${var.project_name}-${var.queue_name}.fifo" : "${var.project_name}-${var.queue_name}"
  dlq_queue_name = var.fifo_queue ? "${var.project_name}-${var.queue_name}-dlq.fifo" : "${var.project_name}-${var.queue_name}-dlq"
}

# ----------------------------------------------
# Dead-Letter Queue
# ----------------------------------------------
resource "aws_sqs_queue" "dlq" {
  name       = local.dlq_queue_name
  fifo_queue = var.fifo_queue

  # Encryption
  sqs_managed_sse_enabled   = var.kms_key_arn == null ? true : null
  kms_master_key_id         = var.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_key_arn != null ? 300 : null

  message_retention_seconds = 1209600 # 14 days max retention for DLQ

  tags = merge(var.tags, {
    Name = local.dlq_queue_name
  })
}

# ----------------------------------------------
# Main Queue
# ----------------------------------------------
resource "aws_sqs_queue" "this" {
  name       = local.queue_name
  fifo_queue = var.fifo_queue

  # Encryption
  sqs_managed_sse_enabled   = var.kms_key_arn == null ? true : null
  kms_master_key_id         = var.kms_key_arn
  kms_data_key_reuse_period_seconds = var.kms_key_arn != null ? 300 : null

  # Message settings
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  max_message_size           = 262144 # 256 KB max
  delay_seconds              = 0
  receive_wait_time_seconds  = 10     # Long polling

  # FIFO-specific settings
  content_based_deduplication = var.fifo_queue ? true : null

  # Redrive policy
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    Name = local.queue_name
  })
}

# ----------------------------------------------
# DLQ Redrive Allow Policy
# ----------------------------------------------
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

# ----------------------------------------------
# Queue Policy (allow SNS and same-account access)
# ----------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSameAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.this.arn
      },
      {
        Sid       = "AllowSNSPublish"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.this.arn
      }
    ]
  })
}
