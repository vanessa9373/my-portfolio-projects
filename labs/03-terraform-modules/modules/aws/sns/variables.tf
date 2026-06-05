# ============================================================
# SNS Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "topic_name" {
  description = "Name suffix for the SNS topic (combined with project_name)"
  type        = string
}

variable "fifo_topic" {
  description = "Whether to create a FIFO topic instead of a standard topic"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of KMS key for server-side encryption (null for no encryption)"
  type        = string
  default     = null
}

variable "subscriptions" {
  description = "List of SNS subscriptions (protocol: email, sqs, lambda, http, https)"
  type = list(object({
    protocol = string
    endpoint = string
  }))
  default = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
