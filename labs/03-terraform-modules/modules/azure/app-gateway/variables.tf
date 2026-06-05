# ============================================================
# App Gateway Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy resources into"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID dedicated to the Application Gateway"
  type        = string
}

variable "sku_name" {
  description = "SKU name for the Application Gateway (Standard_v2 or WAF_v2)"
  type        = string
  default     = "Standard_v2"
}

variable "sku_capacity" {
  description = "Fixed instance count (used when autoscaling is not configured)"
  type        = number
  default     = 2
}

variable "enable_waf" {
  description = "Enable Web Application Firewall (WAF v2)"
  type        = bool
  default     = false
}

variable "waf_mode" {
  description = "WAF mode: Detection or Prevention"
  type        = string
  default     = "Prevention"
}

variable "backend_pools" {
  description = "List of backend pool configurations"
  type = list(object({
    name                     = string
    fqdns                    = optional(list(string), null)
    ip_addresses             = optional(list(string), null)
    port                     = optional(number, 80)
    protocol                 = optional(string, "Http")
    request_timeout          = optional(number, 30)
    cookie_affinity          = optional(string, "Disabled")
    probe_name               = optional(string, null)
    probe_path               = optional(string, null)
    probe_host               = optional(string, null)
    probe_interval           = optional(number, 30)
    probe_timeout            = optional(number, 30)
    probe_unhealthy_threshold = optional(number, 3)
  }))
}

variable "http_listeners" {
  description = "List of HTTP/HTTPS listener configurations"
  type = list(object({
    name                 = string
    protocol             = string
    ssl_certificate_name = optional(string, null)
    host_name            = optional(string, null)
    host_names           = optional(list(string), null)
  }))
}

variable "routing_rules" {
  description = "List of request routing rule configurations"
  type = list(object({
    name                        = string
    priority                    = number
    rule_type                   = optional(string, "Basic")
    http_listener_name          = string
    backend_address_pool_name   = optional(string, null)
    backend_http_settings_name  = optional(string, null)
    url_path_map_name           = optional(string, null)
    redirect_configuration_name = optional(string, null)
  }))
}

variable "ssl_certificates" {
  description = "List of SSL certificate configurations"
  type = list(object({
    name                = string
    key_vault_secret_id = optional(string, null)
    pfx_data            = optional(string, null)
    pfx_password        = optional(string, null)
  }))
  default = []
}

variable "url_path_maps" {
  description = "List of URL path map configurations for path-based routing"
  type = list(object({
    name                               = string
    default_backend_address_pool_name  = string
    default_backend_http_settings_name = string
    path_rules = list(object({
      name                       = string
      paths                      = list(string)
      backend_address_pool_name  = string
      backend_http_settings_name = string
    }))
  }))
  default = []
}

variable "redirect_configurations" {
  description = "List of redirect configuration objects"
  type = list(object({
    name                 = string
    redirect_type        = string
    target_listener_name = optional(string, null)
    target_url           = optional(string, null)
    include_path         = optional(bool, true)
    include_query_string = optional(bool, true)
  }))
  default = []
}

variable "min_capacity" {
  description = "Minimum capacity for autoscaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum capacity for autoscaling"
  type        = number
  default     = 10
}

variable "identity_ids" {
  description = "List of user-assigned managed identity IDs (required for Key Vault SSL certs)"
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
