# ============================================================
# S3 Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "bucket_name" {
  description = "Suffix for the S3 bucket name (combined with project_name)"
  type        = string
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of KMS key for server-side encryption (null for AES256)"
  type        = string
  default     = null
}

variable "lifecycle_rules" {
  description = "Lifecycle rule configuration for object transitions and expiration"
  type = object({
    transition_ia_days      = number
    transition_glacier_days = number
    expiration_days         = number
  })
  default = {
    transition_ia_days      = 30
    transition_glacier_days = 90
    expiration_days         = 365
  }
}

variable "enable_replication" {
  description = "Enable cross-region replication for the bucket"
  type        = bool
  default     = false
}

variable "replication_dest_bucket_arn" {
  description = "ARN of the destination bucket for replication"
  type        = string
  default     = null
}

variable "cors_rules" {
  description = "List of CORS rules for the S3 bucket"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = list(string)
    max_age_seconds = number
  }))
  default = []
}

variable "logging_bucket" {
  description = "Target bucket name for S3 access logging (null to disable)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
