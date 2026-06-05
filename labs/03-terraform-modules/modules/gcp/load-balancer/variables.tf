# ============================================================
# Load Balancer Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where the load balancer will be created"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the SSL certificate and host rules"
  type        = string
}

variable "backends" {
  description = "List of backend service configurations with health check settings"
  type = list(object({
    name              = string
    group             = string
    port              = number
    protocol          = string
    health_check_path = string
    path              = optional(string)
  }))
}

variable "enable_cdn" {
  description = "Enable Cloud CDN on backend services for caching"
  type        = bool
  default     = false
}

variable "cdn_config" {
  description = "Cloud CDN configuration for cache behavior"
  type        = map(any)
  default = {
    cache_mode  = "CACHE_ALL_STATIC"
    default_ttl = 3600
    max_ttl     = 86400
    client_ttl  = 3600
  }
}

variable "ssl_certificates" {
  description = "List of existing SSL certificate self-links (empty to create managed cert)"
  type        = list(string)
  default     = []
}

variable "security_policy" {
  description = "Cloud Armor security policy self-link to attach to backends (null to skip)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Labels to apply to all load balancer resources"
  type        = map(string)
  default     = {}
}
