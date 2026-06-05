# ============================================================
# Pub/Sub Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where Pub/Sub resources will be created"
  type        = string
}

variable "topic_name" {
  description = "Name suffix for the Pub/Sub topic (prefixed with project_name)"
  type        = string
}

variable "subscriptions" {
  description = "List of subscription configurations including push endpoints and retry"
  type = list(object({
    name              = string
    push_endpoint     = optional(string)
    ack_deadline      = optional(number, 20)
    message_retention = optional(number, 604800)
    enable_ordering   = optional(bool, false)
    retry_policy = optional(object({
      minimum_backoff = optional(string, "10s")
      maximum_backoff = optional(string, "600s")
    }))
  }))
  default = []
}

variable "enable_dead_letter" {
  description = "Enable a dead-letter topic for failed message delivery"
  type        = bool
  default     = false
}

variable "dead_letter_max_delivery_attempts" {
  description = "Maximum delivery attempts before sending to the dead-letter topic"
  type        = number
  default     = 5
}

variable "kms_key_name" {
  description = "Cloud KMS key name for CMEK encryption of messages (null for Google-managed)"
  type        = string
  default     = null
}

variable "schema" {
  description = "Schema configuration: type (AVRO/PROTOCOL_BUFFER), definition, encoding"
  type = object({
    type       = optional(string, "AVRO")
    definition = string
    encoding   = optional(string, "JSON")
  })
  default = null
}

variable "tags" {
  description = "Labels to apply to all Pub/Sub resources"
  type        = map(string)
  default     = {}
}
