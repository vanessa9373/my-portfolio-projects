terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
  }

  backend "s3" {
    bucket         = "vanessa-terraform-state"
    key            = "serverless-task-api/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "serverless-task-api"
      Owner     = "Vanessa Awo"
      ManagedBy = "Terraform"
    }
  }
}

locals {
  name_prefix = "task-api-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── DYNAMODB TABLE ───────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "tasks" {
  name         = "${local.name_prefix}-tasks"
  billing_mode = "PAY_PER_REQUEST"  # Serverless — no capacity planning
  hash_key     = "taskId"

  attribute {
    name = "taskId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  # GSI: query tasks by status + createdAt (e.g. all pending tasks, newest first)
  global_secondary_index {
    name            = "StatusCreatedAtIndex"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  # TTL: automatically purge cancelled/deleted tasks after 7 days
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery — restore to any second in last 35 days
  point_in_time_recovery { enabled = true }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-tasks" }
}

# ─── LAMBDA PACKAGING ─────────────────────────────────────────────────────────

data "archive_file" "create_task" {
  type        = "zip"
  source_file = "${path.module}/../src/handlers/create_task.py"
  output_path = "${path.module}/.build/create_task.zip"
}

data "archive_file" "get_task" {
  type        = "zip"
  source_file = "${path.module}/../src/handlers/get_task.py"
  output_path = "${path.module}/.build/get_task.zip"
}

data "archive_file" "list_tasks" {
  type        = "zip"
  source_file = "${path.module}/../src/handlers/list_tasks.py"
  output_path = "${path.module}/.build/list_tasks.zip"
}

data "archive_file" "update_task" {
  type        = "zip"
  source_file = "${path.module}/../src/handlers/update_task.py"
  output_path = "${path.module}/.build/update_task.zip"
}

data "archive_file" "delete_task" {
  type        = "zip"
  source_file = "${path.module}/../src/handlers/delete_task.py"
  output_path = "${path.module}/.build/delete_task.zip"
}

# ─── IAM ROLE FOR LAMBDA ──────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "dynamodb-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
        ]
        Resource = [
          aws_dynamodb_table.tasks.arn,
          "${aws_dynamodb_table.tasks.arn}/index/*",
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ─── LAMBDA FUNCTIONS ─────────────────────────────────────────────────────────

locals {
  lambda_common = {
    runtime       = "python3.12"
    role          = aws_iam_role.lambda.arn
    architectures = ["arm64"]  # Graviton2 — 20% cheaper, faster cold starts
    timeout       = 10
    memory_size   = 256
    environment   = { TABLE_NAME = aws_dynamodb_table.tasks.name }

    tracing_config = { mode = "Active" }  # X-Ray distributed tracing
  }
}

resource "aws_lambda_function" "create_task" {
  function_name    = "${local.name_prefix}-create-task"
  filename         = data.archive_file.create_task.output_path
  source_code_hash = data.archive_file.create_task.output_base64sha256
  handler          = "create_task.lambda_handler"
  runtime          = local.lambda_common.runtime
  role             = local.lambda_common.role
  architectures    = local.lambda_common.architectures
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory_size

  environment { variables = local.lambda_common.environment }
  tracing_config  { mode = "Active" }

  tags = { Name = "${local.name_prefix}-create-task" }
}

resource "aws_lambda_function" "get_task" {
  function_name    = "${local.name_prefix}-get-task"
  filename         = data.archive_file.get_task.output_path
  source_code_hash = data.archive_file.get_task.output_base64sha256
  handler          = "get_task.lambda_handler"
  runtime          = local.lambda_common.runtime
  role             = local.lambda_common.role
  architectures    = local.lambda_common.architectures
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory_size

  environment { variables = local.lambda_common.environment }
  tracing_config  { mode = "Active" }

  tags = { Name = "${local.name_prefix}-get-task" }
}

resource "aws_lambda_function" "list_tasks" {
  function_name    = "${local.name_prefix}-list-tasks"
  filename         = data.archive_file.list_tasks.output_path
  source_code_hash = data.archive_file.list_tasks.output_base64sha256
  handler          = "list_tasks.lambda_handler"
  runtime          = local.lambda_common.runtime
  role             = local.lambda_common.role
  architectures    = local.lambda_common.architectures
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory_size

  environment { variables = local.lambda_common.environment }
  tracing_config  { mode = "Active" }

  tags = { Name = "${local.name_prefix}-list-tasks" }
}

resource "aws_lambda_function" "update_task" {
  function_name    = "${local.name_prefix}-update-task"
  filename         = data.archive_file.update_task.output_path
  source_code_hash = data.archive_file.update_task.output_base64sha256
  handler          = "update_task.lambda_handler"
  runtime          = local.lambda_common.runtime
  role             = local.lambda_common.role
  architectures    = local.lambda_common.architectures
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory_size

  environment { variables = local.lambda_common.environment }
  tracing_config  { mode = "Active" }

  tags = { Name = "${local.name_prefix}-update-task" }
}

resource "aws_lambda_function" "delete_task" {
  function_name    = "${local.name_prefix}-delete-task"
  filename         = data.archive_file.delete_task.output_path
  source_code_hash = data.archive_file.delete_task.output_base64sha256
  handler          = "delete_task.lambda_handler"
  runtime          = local.lambda_common.runtime
  role             = local.lambda_common.role
  architectures    = local.lambda_common.architectures
  timeout          = local.lambda_common.timeout
  memory_size      = local.lambda_common.memory_size

  environment { variables = local.lambda_common.environment }
  tracing_config  { mode = "Active" }

  tags = { Name = "${local.name_prefix}-delete-task" }
}

# ─── API GATEWAY HTTP API ─────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "Serverless Task Management API"

  cors_configuration {
    allow_headers = ["Content-Type", "Authorization"]
    allow_methods = ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      method         = "$context.httpMethod"
      path           = "$context.path"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
      error          = "$context.error.message"
    })
  }

  default_route_settings {
    throttling_burst_limit = 1000
    throttling_rate_limit  = 500
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/api-gateway/${local.name_prefix}"
  retention_in_days = 30
}

# Integrations and routes
locals {
  routes = {
    "POST /tasks"             = { function = aws_lambda_function.create_task }
    "GET /tasks/{taskId}"     = { function = aws_lambda_function.get_task }
    "GET /tasks"              = { function = aws_lambda_function.list_tasks }
    "PATCH /tasks/{taskId}"   = { function = aws_lambda_function.update_task }
    "DELETE /tasks/{taskId}"  = { function = aws_lambda_function.delete_task }
  }
}

resource "aws_apigatewayv2_integration" "lambdas" {
  for_each = local.routes

  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.function.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.lambdas[each.key].id}"
}

resource "aws_lambda_permission" "api_gw" {
  for_each = local.routes

  statement_id  = "allow-api-gw-${replace(each.key, " ", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# ─── CLOUDWATCH ALARMS ────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = {
    create = aws_lambda_function.create_task.function_name
    list   = aws_lambda_function.list_tasks.function_name
    get    = aws_lambda_function.get_task.function_name
    update = aws_lambda_function.update_task.function_name
    delete = aws_lambda_function.delete_task.function_name
  }

  alarm_name          = "${local.name_prefix}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  alarm_description   = "Lambda ${each.value} error count > 5 in 1 minute"

  metric_name = "Errors"
  namespace   = "AWS/Lambda"
  period      = 60
  statistic   = "Sum"
  dimensions  = { FunctionName = each.value }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name_prefix}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 10
  alarm_description   = "API Gateway 5xx errors > 10 in 1 minute"

  metric_name = "5XXError"
  namespace   = "AWS/ApiGateway"
  period      = 60
  statistic   = "Sum"
  dimensions = {
    ApiId = aws_apigatewayv2_api.main.id
    Stage = var.environment
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
