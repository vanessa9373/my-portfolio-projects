# ============================================================
# DynamoDB Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "table_name" {
  description = "Name suffix for the DynamoDB table (combined with project_name)"
  type        = string
}

variable "hash_key" {
  description = "Attribute name to use as the hash (partition) key"
  type        = string
}

variable "range_key" {
  description = "Attribute name to use as the range (sort) key"
  type        = string
  default     = null
}

variable "attributes" {
  description = "List of attribute definitions for the table and its indexes"
  type = list(object({
    name = string
    type = string
  }))
}

variable "billing_mode" {
  description = "DynamoDB billing mode: PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Provisioned read capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "write_capacity" {
  description = "Provisioned write capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "global_secondary_indexes" {
  description = "List of global secondary index definitions"
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(list(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default = []
}

variable "local_secondary_indexes" {
  description = "List of local secondary index definitions"
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string))
  }))
  default = []
}

variable "ttl_attribute" {
  description = "Name of the attribute to use for TTL (null to disable)"
  type        = string
  default     = null
}

variable "enable_pitr" {
  description = "Enable point-in-time recovery"
  type        = bool
  default     = true
}

variable "stream_view_type" {
  description = "DynamoDB stream view type: NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, KEYS_ONLY (null to disable)"
  type        = string
  default     = null

  validation {
    condition     = var.stream_view_type == null || contains(["NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES", "KEYS_ONLY"], coalesce(var.stream_view_type, "NEW_IMAGE"))
    error_message = "stream_view_type must be NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, or KEYS_ONLY."
  }
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (null for AWS-owned key)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
