# ============================================================
# AWS Complete Example — Production Environment
# Composes all AWS modules into a full-stack deployment
# Author: Jenella Awo
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ACM certificates for CloudFront must be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# ============================================================
# Variables
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "domain_name" {
  description = "Primary domain name for the application"
  type        = string
  default     = "example.com"
}

variable "db_master_username" {
  description = "Master username for the RDS cluster"
  type        = string
  sensitive   = true
}

variable "db_master_password" {
  description = "Master password for the RDS cluster"
  type        = string
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Auth token for Redis cluster"
  type        = string
  sensitive   = true
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for ALB HTTPS listener"
  type        = string
}

variable "cloudfront_acm_certificate_arn" {
  description = "ARN of ACM certificate in us-east-1 for CloudFront"
  type        = string
}

variable "notification_email" {
  description = "Email address for alarm notifications"
  type        = string
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ============================================================
# Networking — VPC (existing module)
# ============================================================

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 3
}

# ============================================================
# Security Groups
# ============================================================

module "sg_alb" {
  source = "../../modules/aws/security-group"

  project_name = var.project_name
  sg_name      = "alb"
  vpc_id       = module.vpc.vpc_id
  description  = "Security group for Application Load Balancer"

  ingress_rules = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTP from internet"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow HTTPS from internet"
    }
  ]

  tags = local.common_tags
}

module "sg_app" {
  source = "../../modules/aws/security-group"

  project_name = var.project_name
  sg_name      = "app"
  vpc_id       = module.vpc.vpc_id
  description  = "Security group for application containers"

  ingress_rules = [
    {
      from_port                = 8080
      to_port                  = 8080
      protocol                 = "tcp"
      source_security_group_id = module.sg_alb.security_group_id
      description              = "Allow traffic from ALB"
    }
  ]

  tags = local.common_tags
}

module "sg_database" {
  source = "../../modules/aws/security-group"

  project_name = var.project_name
  sg_name      = "database"
  vpc_id       = module.vpc.vpc_id
  description  = "Security group for RDS Aurora"

  ingress_rules = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = module.sg_app.security_group_id
      description              = "Allow PostgreSQL from app layer"
    }
  ]

  tags = local.common_tags
}

module "sg_redis" {
  source = "../../modules/aws/security-group"

  project_name = var.project_name
  sg_name      = "redis"
  vpc_id       = module.vpc.vpc_id
  description  = "Security group for ElastiCache Redis"

  ingress_rules = [
    {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = module.sg_app.security_group_id
      description              = "Allow Redis from app layer"
    }
  ]

  tags = local.common_tags
}

module "sg_lambda" {
  source = "../../modules/aws/security-group"

  project_name = var.project_name
  sg_name      = "lambda"
  vpc_id       = module.vpc.vpc_id
  description  = "Security group for Lambda functions in VPC"

  ingress_rules = []

  tags = local.common_tags
}

# ============================================================
# S3 Buckets
# ============================================================

module "s3_assets" {
  source = "../../modules/aws/s3"

  project_name      = var.project_name
  bucket_name       = "assets-${var.environment}"
  enable_versioning = true

  lifecycle_rules = {
    transition_ia_days      = 30
    transition_glacier_days = 90
    expiration_days         = 365
  }

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = ["https://${var.domain_name}"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]

  tags = local.common_tags
}

module "s3_logs" {
  source = "../../modules/aws/s3"

  project_name      = var.project_name
  bucket_name       = "logs-${var.environment}"
  enable_versioning = false

  lifecycle_rules = {
    transition_ia_days      = 30
    transition_glacier_days = 60
    expiration_days         = 180
  }

  tags = local.common_tags
}

# ============================================================
# IAM Roles
# ============================================================

module "iam_ecs_task" {
  source = "../../modules/aws/iam"

  project_name    = var.project_name
  role_name       = "ecs-task-execution"
  service_principals = ["ecs-tasks.amazonaws.com"]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
  ]

  tags = local.common_tags
}

module "iam_ecs_app" {
  source = "../../modules/aws/iam"

  project_name       = var.project_name
  role_name          = "ecs-app-task"
  service_principals = ["ecs-tasks.amazonaws.com"]

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_assets.bucket_arn,
          "${module.s3_assets.bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = [module.sqs_events.queue_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          module.dynamodb_sessions.table_arn,
          "${module.dynamodb_sessions.table_arn}/index/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# IRSA role for EKS workloads
module "iam_eks_app" {
  source = "../../modules/aws/iam"

  project_name     = var.project_name
  role_name        = "eks-app-irsa"
  oidc_provider_arn = module.eks.oidc_provider_arn

  oidc_conditions = {
    "${replace(module.eks.cluster_endpoint, "https://", "")}:sub" = "system:serviceaccount:default:app-sa"
  }

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${module.s3_assets.bucket_arn}/*"]
      }
    ]
  })

  tags = local.common_tags
}

# ============================================================
# Application Load Balancer
# ============================================================

module "alb" {
  source = "../../modules/aws/alb"

  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.public_subnet_ids
  acm_certificate_arn = var.acm_certificate_arn
  access_logs_bucket  = module.s3_logs.bucket_id
  health_check_path   = "/health"
  target_port         = 8080
  target_type         = "ip"

  enable_deletion_protection = true

  tags = local.common_tags
}

# ============================================================
# EKS Cluster (existing module)
# ============================================================

module "eks" {
  source = "../../modules/eks"

  project_name    = var.project_name
  subnet_ids      = module.vpc.private_subnet_ids
  vpc_id          = module.vpc.vpc_id
  cluster_version = "1.29"
  instance_type   = "t3.large"
  desired_nodes   = 3
  min_nodes       = 2
  max_nodes       = 10
  public_access   = false
}

# ============================================================
# ECR Repositories
# ============================================================

module "ecr_api" {
  source = "../../modules/aws/ecr"

  project_name         = var.project_name
  repository_name      = "api"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  max_image_count      = 50
  untagged_expiry_days = 7

  tags = local.common_tags
}

module "ecr_worker" {
  source = "../../modules/aws/ecr"

  project_name         = var.project_name
  repository_name      = "worker"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  max_image_count      = 50
  untagged_expiry_days = 7

  tags = local.common_tags
}

# ============================================================
# RDS Aurora PostgreSQL (existing module)
# ============================================================

module "rds" {
  source = "../../modules/rds"

  project_name       = var.project_name
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.sg_database.security_group_id]
  database_name      = "appdb"
  master_username    = var.db_master_username
  master_password    = var.db_master_password
  engine_version     = "15.4"
  instance_class     = "db.r6g.xlarge"
  instance_count     = 2
  backup_retention   = 14
  skip_final_snapshot = false
}

# ============================================================
# ElastiCache Redis
# ============================================================

module "elasticache" {
  source = "../../modules/aws/elasticache"

  project_name            = var.project_name
  cluster_name            = "redis"
  engine                  = "redis"
  engine_version          = "7.1"
  node_type               = "cache.r7g.large"
  num_node_groups         = 2
  replicas_per_node_group = 1
  subnet_ids              = module.vpc.private_subnet_ids
  security_group_ids      = [module.sg_redis.security_group_id]
  at_rest_encryption      = true
  transit_encryption      = true
  auth_token              = var.redis_auth_token
  parameter_group_family  = "redis7"

  tags = local.common_tags
}

# ============================================================
# DynamoDB
# ============================================================

module "dynamodb_sessions" {
  source = "../../modules/aws/dynamodb"

  project_name = var.project_name
  table_name   = "sessions"
  hash_key     = "session_id"
  range_key    = "user_id"
  billing_mode = "PAY_PER_REQUEST"

  attributes = [
    { name = "session_id", type = "S" },
    { name = "user_id", type = "S" },
    { name = "created_at", type = "N" }
  ]

  global_secondary_indexes = [
    {
      name            = "user-index"
      hash_key        = "user_id"
      range_key       = "created_at"
      projection_type = "ALL"
    }
  ]

  ttl_attribute    = "expires_at"
  enable_pitr      = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = local.common_tags
}

# ============================================================
# SQS Queues
# ============================================================

module "sqs_events" {
  source = "../../modules/aws/sqs"

  project_name               = var.project_name
  queue_name                 = "events"
  fifo_queue                 = false
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 60
  max_receive_count          = 5

  tags = local.common_tags
}

module "sqs_notifications" {
  source = "../../modules/aws/sqs"

  project_name               = var.project_name
  queue_name                 = "notifications"
  fifo_queue                 = true
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 30
  max_receive_count          = 3

  tags = local.common_tags
}

# ============================================================
# SNS Topics
# ============================================================

module "sns_alerts" {
  source = "../../modules/aws/sns"

  project_name = var.project_name
  topic_name   = "alerts"
  fifo_topic   = false

  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    },
    {
      protocol = "sqs"
      endpoint = module.sqs_notifications.queue_arn
    }
  ]

  tags = local.common_tags
}

# ============================================================
# Lambda Functions
# ============================================================

module "lambda_processor" {
  source = "../../modules/aws/lambda"

  project_name    = var.project_name
  function_name   = "event-processor"
  runtime         = "python3.12"
  handler         = "index.handler"
  filename        = "${path.module}/lambda/processor.zip"
  memory_size     = 256
  timeout         = 60
  log_retention_days = 30

  environment_variables = {
    TABLE_NAME    = module.dynamodb_sessions.table_name
    QUEUE_URL     = module.sqs_events.queue_url
    ENVIRONMENT   = var.environment
  }

  vpc_config = {
    subnet_ids         = module.vpc.private_subnet_ids
    security_group_ids = [module.sg_lambda.security_group_id]
  }

  event_sources = [
    {
      event_source_arn = module.sqs_events.queue_arn
      batch_size       = 10
      enabled          = true
    }
  ]

  tags = local.common_tags
}

module "lambda_api" {
  source = "../../modules/aws/lambda"

  project_name       = var.project_name
  function_name      = "api-handler"
  runtime            = "nodejs20.x"
  handler            = "index.handler"
  filename           = "${path.module}/lambda/api.zip"
  memory_size        = 512
  timeout            = 30
  enable_function_url = true
  log_retention_days  = 14

  environment_variables = {
    REDIS_ENDPOINT = module.elasticache.primary_endpoint
    DB_ENDPOINT    = module.rds.cluster_endpoint
    ENVIRONMENT    = var.environment
  }

  tags = local.common_tags
}

# ============================================================
# CloudFront Distribution
# ============================================================

module "cloudfront" {
  source = "../../modules/aws/cloudfront"

  project_name        = var.project_name
  origin_domain_name  = module.s3_assets.bucket_regional_domain_name
  origin_type         = "s3"
  s3_bucket_arn       = module.s3_assets.bucket_arn
  acm_certificate_arn = var.cloudfront_acm_certificate_arn
  domain_aliases      = ["cdn.${var.domain_name}"]
  default_root_object = "index.html"
  logging_bucket      = "${module.s3_logs.bucket_id}.s3.amazonaws.com"

  custom_error_responses = [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  ]

  tags = local.common_tags
}

# ============================================================
# Route53 DNS
# ============================================================

module "route53" {
  source = "../../modules/aws/route53"

  project_name = var.project_name
  domain_name  = var.domain_name
  private_zone = false

  records = [
    {
      name = var.domain_name
      type = "A"
      alias = {
        name                   = module.alb.alb_dns_name
        zone_id                = module.alb.alb_zone_id
        evaluate_target_health = true
      }
    },
    {
      name = "cdn.${var.domain_name}"
      type = "A"
      alias = {
        name                   = module.cloudfront.distribution_domain_name
        zone_id                = "Z2FDTNDATAQYW2" # CloudFront global hosted zone ID
        evaluate_target_health = false
      }
    },
    {
      name   = "api.${var.domain_name}"
      type   = "CNAME"
      ttl    = 300
      values = [module.alb.alb_dns_name]
    }
  ]

  health_checks = [
    {
      fqdn              = var.domain_name
      port              = 443
      type              = "HTTPS"
      resource_path     = "/health"
      failure_threshold = 3
      request_interval  = 30
    }
  ]

  tags = local.common_tags
}

# ============================================================
# CloudWatch Monitoring
# ============================================================

module "cloudwatch" {
  source = "../../modules/aws/cloudwatch"

  project_name      = var.project_name
  log_group_name    = "application"
  retention_in_days = 30
  sns_topic_arn     = module.sns_alerts.topic_arn

  alarms = [
    {
      name                = "alb-5xx-errors"
      metric_name         = "HTTPCode_ELB_5XX_Count"
      namespace           = "AWS/ApplicationELB"
      statistic           = "Sum"
      threshold           = 10
      comparison_operator = "GreaterThanOrEqualToThreshold"
      period              = 300
      evaluation_periods  = 2
    },
    {
      name                = "alb-target-response-time"
      metric_name         = "TargetResponseTime"
      namespace           = "AWS/ApplicationELB"
      statistic           = "Average"
      threshold           = 5
      comparison_operator = "GreaterThanOrEqualToThreshold"
      period              = 300
      evaluation_periods  = 3
    },
    {
      name                = "rds-cpu-utilization"
      metric_name         = "CPUUtilization"
      namespace           = "AWS/RDS"
      statistic           = "Average"
      threshold           = 80
      comparison_operator = "GreaterThanOrEqualToThreshold"
      period              = 300
      evaluation_periods  = 3
    },
    {
      name                = "redis-memory-usage"
      metric_name         = "DatabaseMemoryUsagePercentage"
      namespace           = "AWS/ElastiCache"
      statistic           = "Average"
      threshold           = 80
      comparison_operator = "GreaterThanOrEqualToThreshold"
      period              = 300
      evaluation_periods  = 2
    },
    {
      name                = "lambda-errors"
      metric_name         = "Errors"
      namespace           = "AWS/Lambda"
      statistic           = "Sum"
      threshold           = 5
      comparison_operator = "GreaterThanOrEqualToThreshold"
      period              = 300
      evaluation_periods  = 2
    },
    {
      name                = "sqs-dlq-messages"
      metric_name         = "ApproximateNumberOfMessagesVisible"
      namespace           = "AWS/SQS"
      statistic           = "Sum"
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      period              = 300
      evaluation_periods  = 1
    }
  ]

  dashboard_widgets = [
    {
      type    = "metric"
      x       = 0
      y       = 0
      width   = 12
      height  = 6
      title   = "ALB Request Count"
      metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/myapp-alb"]]
      region  = "us-west-2"
      period  = 300
      stat    = "Sum"
    },
    {
      type    = "metric"
      x       = 12
      y       = 0
      width   = 12
      height  = 6
      title   = "RDS CPU Utilization"
      metrics = [["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "myapp-aurora"]]
      region  = "us-west-2"
      period  = 300
      stat    = "Average"
    },
    {
      type    = "metric"
      x       = 0
      y       = 6
      width   = 12
      height  = 6
      title   = "Lambda Invocations"
      metrics = [["AWS/Lambda", "Invocations", "FunctionName", "myapp-event-processor"]]
      region  = "us-west-2"
      period  = 300
      stat    = "Sum"
    },
    {
      type    = "metric"
      x       = 12
      y       = 6
      width   = 12
      height  = 6
      title   = "Redis Memory Usage"
      metrics = [["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "ReplicationGroupId", "myapp-redis"]]
      region  = "us-west-2"
      period  = 300
      stat    = "Average"
    }
  ]

  tags = local.common_tags
}

# ============================================================
# Outputs
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "rds_cluster_endpoint" {
  description = "RDS Aurora cluster endpoint"
  value       = module.rds.cluster_endpoint
}

output "rds_reader_endpoint" {
  description = "RDS Aurora reader endpoint"
  value       = module.rds.reader_endpoint
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = module.elasticache.primary_endpoint
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint"
  value       = module.elasticache.reader_endpoint
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = module.cloudfront.distribution_domain_name
}

output "ecr_api_url" {
  description = "ECR repository URL for API service"
  value       = module.ecr_api.repository_url
}

output "ecr_worker_url" {
  description = "ECR repository URL for worker service"
  value       = module.ecr_worker.repository_url
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.route53.zone_id
}

output "route53_name_servers" {
  description = "Route53 name servers"
  value       = module.route53.name_servers
}

output "sns_alerts_topic_arn" {
  description = "SNS alerts topic ARN"
  value       = module.sns_alerts.topic_arn
}

output "sqs_events_queue_url" {
  description = "SQS events queue URL"
  value       = module.sqs_events.queue_url
}

output "dynamodb_sessions_table" {
  description = "DynamoDB sessions table name"
  value       = module.dynamodb_sessions.table_name
}

output "lambda_processor_arn" {
  description = "Lambda event processor function ARN"
  value       = module.lambda_processor.function_arn
}

output "lambda_api_url" {
  description = "Lambda API function URL"
  value       = module.lambda_api.function_url
}

output "cloudwatch_log_group" {
  description = "CloudWatch application log group name"
  value       = module.cloudwatch.log_group_name
}
