# ============================================================
# ACR Module — Variables
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

variable "sku" {
  description = "SKU for the container registry (Basic, Standard, or Premium)"
  type        = string
  default     = "Premium"
}

variable "admin_enabled" {
  description = "Enable the admin user for the container registry"
  type        = bool
  default     = false
}

variable "georeplications" {
  description = "List of geo-replication locations (Premium SKU only)"
  type = list(object({
    location                = string
    zone_redundancy_enabled = optional(bool, false)
  }))
  default = []
}

variable "enable_content_trust" {
  description = "Enable content trust for signed images (Premium SKU only)"
  type        = bool
  default     = false
}

variable "network_rule_set" {
  description = "Network rule set for the container registry (Premium SKU only)"
  type = object({
    default_action             = optional(string, "Allow")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}

variable "retention_days" {
  description = "Number of days to retain untagged manifests (Premium SKU only)"
  type        = number
  default     = 30
}

variable "webhooks" {
  description = "List of webhook configurations for the container registry"
  type = list(object({
    name           = string
    service_uri    = string
    actions        = list(string)
    status         = optional(string, "enabled")
    scope          = optional(string, "")
    custom_headers = optional(map(string), {})
  }))
  default = []
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
