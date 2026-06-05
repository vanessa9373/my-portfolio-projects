# ============================================================
# Lambda Module — Function with IAM Role, VPC Config,
# Event Source Mappings, CloudWatch Logs, and Function URL
# Author: Jenella Awo
# ============================================================

locals {
  function_name = "${var.project_name}-${var.function_name}"
}

# ----------------------------------------------
# IAM Execution Role
# ----------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${local.function_name}-execution-role"
  })
}

# CloudWatch Logs policy
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${local.function_name}-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# VPC access policy (conditional)
resource "aws_iam_role_policy_attachment" "vpc_access" {
  count      = var.vpc_config != null ? 1 : 0
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Event source mapping policy for SQS, DynamoDB, Kinesis
resource "aws_iam_role_policy" "event_source" {
  count = length(var.event_sources) > 0 ? 1 : 0
  name  = "${local.function_name}-event-source"
  role  = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = [for es in var.event_sources : es.event_source_arn]
      }
    ]
  })
}

# ----------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${local.function_name}-logs"
  })
}

# ----------------------------------------------
# Lambda Function
# ----------------------------------------------
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn
  runtime       = var.runtime
  handler       = var.handler
  filename      = var.filename
  memory_size   = var.memory_size
  timeout       = var.timeout

  source_code_hash = filebase64sha256(var.filename)

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_logs,
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(var.tags, {
    Name = local.function_name
  })
}

# ----------------------------------------------
# Event Source Mappings (SQS, DynamoDB, Kinesis)
# ----------------------------------------------
resource "aws_lambda_event_source_mapping" "this" {
  for_each = { for idx, es in var.event_sources : idx => es }

  event_source_arn  = each.value.event_source_arn
  function_name     = aws_lambda_function.this.arn
  batch_size        = lookup(each.value, "batch_size", 10)
  enabled           = lookup(each.value, "enabled", true)
  starting_position = lookup(each.value, "starting_position", null)
}

# ----------------------------------------------
# Lambda Function URL (optional)
# ----------------------------------------------
resource "aws_lambda_function_url" "this" {
  count              = var.enable_function_url ? 1 : 0
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
}
