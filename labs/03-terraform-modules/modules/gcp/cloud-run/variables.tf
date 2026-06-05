# ============================================================
# Cloud Run Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
}

variable "image" {
  description = "Container image URL"
  type        = string
}

variable "port" {
  description = "Container port"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU allocation (e.g., '1', '2', '1000m')"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation (e.g., '512Mi', '1Gi')"
  type        = string
  default     = "512Mi"
}

variable "cpu_idle" {
  description = "Allow CPU to be throttled when no requests"
  type        = bool
  default     = true
}

variable "min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret references from Secret Manager"
  type = list(object({
    env_name    = string
    secret_name = string
    version     = string
  }))
  default = []
}

variable "vpc_connector" {
  description = "VPC connector for private network access"
  type        = string
  default     = null
}

variable "service_account_email" {
  description = "Service account email for the Cloud Run service"
  type        = string
  default     = null
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated (public) access"
  type        = bool
  default     = false
}

variable "custom_domain" {
  description = "Custom domain mapping"
  type        = string
  default     = null
}

variable "traffic" {
  description = "Traffic splitting configuration"
  type = list(object({
    revision = string
    percent  = number
  }))
  default = [{
    revision = "latest"
    percent  = 100
  }]
}

variable "tags" {
  description = "Labels to apply to the service"
  type        = map(string)
  default     = {}
}
