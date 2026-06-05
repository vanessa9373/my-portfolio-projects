variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "ha-wordpress"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens only."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "domain_name" {
  description = "Root domain name (must be in Route 53)"
  type        = string
  default     = "vanessaawo.com"
}

# ─── NETWORK ──────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private app subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

# ─── COMPUTE ──────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type for WordPress servers"
  type        = string
  default     = "t3.medium"
}

variable "ec2_key_pair_name" {
  description = "Name of existing EC2 key pair for SSH access (SSM preferred)"
  type        = string
  default     = ""
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the ASG"
  type        = number
  default     = 10
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the ASG"
  type        = number
  default     = 2
}

# ─── DATABASE ─────────────────────────────────────────────────────────────────

variable "db_name" {
  description = "WordPress database name"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "Database admin username"
  type        = string
  default     = "wpadmin"
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

# ─── ALERTING ─────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = "jenellaawo93@gmail.com"
}
