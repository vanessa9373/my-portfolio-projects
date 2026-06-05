# ============================================================
# Cloud Storage Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for the bucket name"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where the bucket will be created"
  type        = string
}

variable "bucket_name" {
  description = "Suffix for the bucket name (will be prefixed with project_name)"
  type        = string
}

variable "location" {
  description = "GCS bucket location (region, dual-region, or multi-region)"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Default storage class: STANDARD, NEARLINE, COLDLINE, or ARCHIVE"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "storage_class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_versioning" {
  description = "Enable object versioning on the bucket"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "List of lifecycle rule configurations for automatic object management"
  type = list(object({
    action_type           = string
    storage_class         = optional(string)
    age_days              = optional(number)
    created_before        = optional(string)
    with_state            = optional(string)
    num_newer_versions    = optional(number)
    matches_storage_class = optional(list(string))
  }))
  default = []
}

variable "uniform_access" {
  description = "Enable uniform bucket-level access (recommended over ACLs)"
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Cloud KMS key name for CMEK encryption (null for Google-managed)"
  type        = string
  default     = null
}

variable "cors_rules" {
  description = "List of CORS rule configurations for browser-based uploads"
  type = list(object({
    origins          = list(string)
    methods          = list(string)
    response_headers = optional(list(string), [])
    max_age_seconds  = optional(number, 3600)
  }))
  default = []
}

variable "retention_period_days" {
  description = "Minimum retention period in days (null to disable)"
  type        = number
  default     = null
}

variable "logging_bucket" {
  description = "Target bucket name for access log storage (null to disable)"
  type        = string
  default     = null
}

variable "enable_website" {
  description = "Enable static website hosting configuration"
  type        = bool
  default     = false
}

variable "website_config" {
  description = "Website configuration for main page and error page"
  type        = map(string)
  default = {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

variable "tags" {
  description = "Labels to apply to the GCS bucket"
  type        = map(string)
  default     = {}
}
