# ============================================================
# ALB Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS listener"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the ALB"
  type        = bool
  default     = true
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs (null to disable)"
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Health check path for the default target group"
  type        = string
  default     = "/health"
}

variable "target_port" {
  description = "Port on which targets receive traffic"
  type        = number
  default     = 80
}

variable "target_type" {
  description = "Type of target for the target group (instance, ip, lambda)"
  type        = string
  default     = "ip"
}

variable "ingress_cidrs" {
  description = "List of CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
