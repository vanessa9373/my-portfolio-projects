# ============================================================
# SQS Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "queue_name" {
  description = "Name suffix for the SQS queue (combined with project_name)"
  type        = string
}

variable "fifo_queue" {
  description = "Whether to create a FIFO queue instead of a standard queue"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (null for SQS-managed SSE)"
  type        = string
  default     = null
}

variable "message_retention_seconds" {
  description = "Number of seconds SQS retains a message (60 to 1209600)"
  type        = number
  default     = 345600 # 4 days
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for the queue in seconds (0 to 43200)"
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "Number of times a message is received before being sent to the DLQ"
  type        = number
  default     = 5
}

variable "dlq_max_receive_count" {
  description = "Max receive count for DLQ redrive (reserved for future use)"
  type        = number
  default     = 5
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
