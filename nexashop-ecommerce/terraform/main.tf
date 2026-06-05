locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── Networking ────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# ── CDN + Frontend ────────────────────────────────────────────────────────────
module "cdn" {
  source = "./modules/cdn"

  name_prefix         = local.name_prefix
  domain_name         = var.domain_name
  acm_certificate_arn = var.acm_certificate_arn

  providers = {
    aws          = aws
    aws.us_east_1 = aws.us_east_1
  }
}

# ── ECS Fargate API ───────────────────────────────────────────────────────────
module "ecs" {
  source = "./modules/ecs"

  name_prefix      = local.name_prefix
  vpc_id           = module.vpc.vpc_id
  private_subnets  = module.vpc.private_subnet_ids
  public_subnets   = module.vpc.public_subnet_ids
  ecr_image_uri    = var.ecr_image_uri
  cpu              = var.ecs_cpu
  memory           = var.ecs_memory
  desired_count    = var.ecs_desired_count

  db_secret_arn    = module.rds.db_secret_arn
  db_host          = module.rds.cluster_endpoint
  redis_endpoint   = module.elasticache.redis_endpoint
  cognito_user_pool_id     = module.cognito.user_pool_id
  cognito_app_client_id    = module.cognito.app_client_id
}

# ── Aurora PostgreSQL (Orders DB) ─────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  isolated_subnets   = module.vpc.isolated_subnet_ids
  allowed_sg_ids     = [module.ecs.ecs_security_group_id]
  instance_class     = var.rds_instance_class
  database_name      = var.rds_database_name
}

# ── DynamoDB (Product Catalog) ────────────────────────────────────────────────
resource "aws_dynamodb_table" "products" {
  name         = "${local.name_prefix}-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "productId"

  attribute {
    name = "productId"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "category-createdAt-index"
    hash_key        = "category"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery { enabled = true }
  server_side_encryption  { enabled = true }

  tags = { Name = "${local.name_prefix}-products" }
}

# ── ElastiCache Redis (Sessions + Cart) ───────────────────────────────────────
module "elasticache" {
  source = "./modules/elasticache"

  name_prefix      = local.name_prefix
  vpc_id           = module.vpc.vpc_id
  isolated_subnets = module.vpc.isolated_subnet_ids
  allowed_sg_ids   = [module.ecs.ecs_security_group_id]
}

# ── SQS (Order Queue) ─────────────────────────────────────────────────────────
resource "aws_sqs_queue" "order_dlq" {
  name                      = "${local.name_prefix}-orders-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = aws_kms_key.nexashop.arn
}

resource "aws_sqs_queue" "orders" {
  name                       = "${local.name_prefix}-orders"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  kms_master_key_id          = aws_kms_key.nexashop.arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })
}

# ── KMS Key ───────────────────────────────────────────────────────────────────
resource "aws_kms_key" "nexashop" {
  description             = "NexaShop encryption key — DynamoDB, RDS, S3, Secrets Manager"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "nexashop" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.nexashop.key_id
}

# ── Cognito ───────────────────────────────────────────────────────────────────
module "cognito" {
  source = "./modules/cognito"

  name_prefix   = local.name_prefix
  domain_name   = var.domain_name
  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name_prefix}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "API Gateway 5XX errors exceeded threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "order_queue_depth" {
  alarm_name          = "${local.name_prefix}-order-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 500
  alarm_description   = "Order queue depth unexpectedly high — possible processing failure"
  dimensions          = { QueueName = aws_sqs_queue.orders.name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = aws_kms_key.nexashop.arn
}
