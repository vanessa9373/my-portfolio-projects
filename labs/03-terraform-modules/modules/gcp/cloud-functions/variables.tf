# ============================================================
# Cloud Functions Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where the Cloud Function will be deployed"
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Function deployment"
  type        = string
  default     = "us-central1"
}

variable "function_name" {
  description = "Name suffix for the Cloud Function (prefixed with project_name)"
  type        = string
}

variable "runtime" {
  description = "Runtime environment (e.g., nodejs20, python312, go122, java17)"
  type        = string
  default     = "python312"
}

variable "entry_point" {
  description = "Name of the function to execute as the entry point"
  type        = string
}

variable "source_dir" {
  description = "Path to the directory containing the function source code"
  type        = string
}

variable "trigger_type" {
  description = "Type of trigger: http, pubsub, or storage"
  type        = string
  default     = "http"

  validation {
    condition     = contains(["http", "pubsub", "storage"], var.trigger_type)
    error_message = "trigger_type must be one of: http, pubsub, storage."
  }
}

variable "trigger_config" {
  description = "Trigger-specific configuration (topic for pubsub, bucket for storage, etc.)"
  type        = map(any)
  default     = {}
}

variable "environment_variables" {
  description = "Environment variables to set on the Cloud Function"
  type        = map(string)
  default     = {}
}

variable "vpc_connector" {
  description = "VPC connector self-link for private VPC access"
  type        = string
  default     = null
}

variable "min_instances" {
  description = "Minimum number of instances to keep warm (0 for scale to zero)"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of concurrent instances"
  type        = number
  default     = 100
}

variable "memory" {
  description = "Amount of memory allocated to the function (e.g., 256Mi, 512Mi, 1Gi)"
  type        = string
  default     = "256Mi"
}

variable "timeout" {
  description = "Maximum execution time in seconds before the function times out"
  type        = number
  default     = 60
}

variable "service_account_email" {
  description = "Service account email for the function's runtime identity"
  type        = string
  default     = null
}

variable "tags" {
  description = "Labels to apply to all Cloud Function resources"
  type        = map(string)
  default     = {}
}
