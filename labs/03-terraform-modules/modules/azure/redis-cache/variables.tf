# ============================================================
# Azure Redis Cache Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "sku_name" {
  description = "Redis SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "family" {
  description = "Redis family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "capacity" {
  description = "Redis cache capacity (0-6 for C family, 1-5 for P family)"
  type        = number
  default     = 1
}

variable "enable_non_ssl" {
  description = "Enable non-SSL port (6379)"
  type        = bool
  default     = false
}

variable "minimum_tls_version" {
  description = "Minimum TLS version"
  type        = string
  default     = "1.2"
}

variable "subnet_id" {
  description = "Subnet ID for VNet integration (Premium only)"
  type        = string
  default     = null
}

variable "redis_configuration" {
  description = "Redis configuration options"
  type = object({
    maxmemory_reserved              = optional(number, 50)
    maxmemory_delta                 = optional(number, 50)
    maxmemory_policy                = optional(string, "volatile-lru")
    maxfragmentationmemory_reserved = optional(number, 50)
    rdb_backup_enabled              = optional(bool, false)
    rdb_backup_frequency            = optional(number, 60)
    rdb_backup_max_snapshot_count   = optional(number, 1)
    rdb_storage_connection_string   = optional(string, null)
  })
  default = {}
}

variable "firewall_rules" {
  description = "List of firewall rules"
  type = list(object({
    name     = string
    start_ip = string
    end_ip   = string
  }))
  default = []
}

variable "patch_schedule" {
  description = "Patch schedule configuration"
  type = object({
    day_of_week        = string
    start_hour_utc     = optional(number, 2)
    maintenance_window = optional(string, "PT5H")
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
