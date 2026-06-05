# ============================================================
# Azure Front Door Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "backend_pools" {
  description = "Backend pool configurations"
  type = list(object({
    name                  = string
    host_name             = string
    health_probe_path     = optional(string, "/health")
    health_probe_protocol = optional(string, "Https")
    session_affinity      = optional(bool, false)
    latency_sensitivity   = optional(number, 0)
    priority              = optional(number, 1)
    weight                = optional(number, 50)
  }))
}

variable "routing_rules" {
  description = "Routing rule configurations"
  type = list(object({
    name                 = string
    backend_pool         = string
    patterns_to_match    = list(string)
    forwarding_protocol  = optional(string, "HttpsOnly")
    enable_caching       = optional(bool, false)
  }))
}

variable "enable_waf" {
  description = "Enable WAF policy"
  type        = bool
  default     = false
}

variable "waf_mode" {
  description = "WAF mode (Prevention or Detection)"
  type        = string
  default     = "Prevention"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
