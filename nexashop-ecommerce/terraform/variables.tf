variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod"
  }
}

variable "project_name" {
  description = "Project identifier used in resource names"
  type        = string
  default     = "nexashop"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy resources into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# ── ECS ──────────────────────────────────────────────────────────────────────
variable "ecs_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "ecs_memory" {
  description = "Fargate task memory in MB"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS task replicas"
  type        = number
  default     = 2
}

variable "ecr_image_uri" {
  description = "Full ECR image URI for the API container"
  type        = string
}

# ── RDS ──────────────────────────────────────────────────────────────────────
variable "rds_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_database_name" {
  description = "Initial database name"
  type        = string
  default     = "nexashop"
}

# ── CDN ──────────────────────────────────────────────────────────────────────
variable "domain_name" {
  description = "Primary domain name (e.g. nexashop.com)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN (must be in us-east-1 for CloudFront)"
  type        = string
}

# ── Cognito ───────────────────────────────────────────────────────────────────
variable "cognito_callback_urls" {
  description = "Allowed OAuth callback URLs for Cognito"
  type        = list(string)
  default     = []
}

variable "cognito_logout_urls" {
  description = "Allowed logout URLs for Cognito"
  type        = list(string)
  default     = []
}
