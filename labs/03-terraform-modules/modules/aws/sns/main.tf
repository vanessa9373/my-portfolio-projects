# ============================================================
# SNS Module — Standard/FIFO Topic with KMS Encryption,
# Subscriptions, Topic Policy, and Delivery Status Logging
# Author: Jenella Awo
# ============================================================

locals {
  topic_name = var.fifo_topic ? "${var.project_name}-${var.topic_name}.fifo" : "${var.project_name}-${var.topic_name}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------
# SNS Topic
# ----------------------------------------------
resource "aws_sns_topic" "this" {
  name              = local.topic_name
  fifo_topic        = var.fifo_topic
  kms_master_key_id = var.kms_key_arn

  # FIFO-specific settings
  content_based_deduplication = var.fifo_topic ? true : null

  # Delivery status logging for Lambda
  lambda_success_feedback_role_arn    = aws_iam_role.delivery_status.arn
  lambda_failure_feedback_role_arn    = aws_iam_role.delivery_status.arn
  lambda_success_feedback_sample_rate = 100

  # Delivery status logging for SQS
  sqs_success_feedback_role_arn    = aws_iam_role.delivery_status.arn
  sqs_failure_feedback_role_arn    = aws_iam_role.delivery_status.arn
  sqs_success_feedback_sample_rate = 100

  tags = merge(var.tags, {
    Name = local.topic_name
  })
}

# ----------------------------------------------
# Topic Policy
# ----------------------------------------------
resource "aws_sns_topic_policy" "this" {
  arn = aws_sns_topic.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSameAccountPublish"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.this.arn
      },
      {
        Sid       = "AllowSameAccountSubscribe"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action = [
          "sns:Subscribe",
          "sns:Receive"
        ]
        Resource = aws_sns_topic.this.arn
      },
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.this.arn
      }
    ]
  })
}

# ----------------------------------------------
# Subscriptions
# ----------------------------------------------
resource "aws_sns_topic_subscription" "this" {
  for_each = { for idx, sub in var.subscriptions : idx => sub }

  topic_arn = aws_sns_topic.this.arn
  protocol  = each.value.protocol
  endpoint  = each.value.endpoint

  # Raw message delivery for SQS/HTTP endpoints
  raw_message_delivery = contains(["sqs", "http", "https"], each.value.protocol) ? true : false
}

# ----------------------------------------------
# Delivery Status Logging IAM Role
# ----------------------------------------------
resource "aws_iam_role" "delivery_status" {
  name = "${var.project_name}-${var.topic_name}-sns-delivery-status"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.topic_name}-sns-delivery-status"
  })
}

resource "aws_iam_role_policy" "delivery_status" {
  name = "${var.project_name}-${var.topic_name}-sns-delivery-logs"
  role = aws_iam_role.delivery_status.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutMetricFilter",
          "logs:PutRetentionPolicy"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:sns/${data.aws_region.current.name}/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}
