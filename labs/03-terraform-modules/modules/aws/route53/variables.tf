# ============================================================
# Route53 Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
}

variable "private_zone" {
  description = "Whether to create a private hosted zone"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID to associate with the private hosted zone (required if private_zone is true)"
  type        = string
  default     = null
}

variable "records" {
  description = "List of DNS records to create in the hosted zone"
  type = list(object({
    name   = string
    type   = string
    ttl    = optional(number, 300)
    values = optional(list(string), [])
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = bool
    }))
  }))
  default = []
}

variable "health_checks" {
  description = "List of Route53 health checks to create"
  type = list(object({
    fqdn              = string
    port               = number
    type               = string
    resource_path      = string
    failure_threshold  = optional(number, 3)
    request_interval   = optional(number, 30)
  }))
  default = []
}

variable "enable_dnssec" {
  description = "Whether to enable DNSSEC for the hosted zone (public zones only)"
  type        = bool
  default     = false
}

variable "dnssec_kms_key_arn" {
  description = "ARN of KMS key for DNSSEC signing (required if enable_dnssec is true)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
