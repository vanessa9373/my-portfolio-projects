# ============================================================
# Storage Account Module — Variables
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

variable "account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "account_replication_type" {
  description = "Storage account replication type (LRS, GRS, ZRS, RAGRS, GZRS, RAGZRS)"
  type        = string
  default     = "GRS"
}

variable "account_kind" {
  description = "Storage account kind (StorageV2, BlobStorage, BlockBlobStorage, FileStorage)"
  type        = string
  default     = "StorageV2"
}

variable "containers" {
  description = "List of blob containers to create"
  type = list(object({
    name        = string
    access_type = optional(string, "private")
  }))
  default = []
}

variable "file_shares" {
  description = "List of file shares to create"
  type = list(object({
    name        = string
    quota       = optional(number, 50)
    access_tier = optional(string, "TransactionOptimized")
  }))
  default = []
}

variable "enable_static_website" {
  description = "Enable static website hosting on the storage account"
  type        = bool
  default     = false
}

variable "index_document" {
  description = "Index document for static website hosting"
  type        = string
  default     = "index.html"
}

variable "error_404_document" {
  description = "Error 404 document for static website hosting"
  type        = string
  default     = "404.html"
}

variable "enable_versioning" {
  description = "Enable blob versioning"
  type        = bool
  default     = true
}

variable "enable_change_feed" {
  description = "Enable blob change feed"
  type        = bool
  default     = true
}

variable "blob_soft_delete_days" {
  description = "Number of days for blob soft delete retention (0 to disable)"
  type        = number
  default     = 30
}

variable "container_soft_delete_days" {
  description = "Number of days for container soft delete retention (0 to disable)"
  type        = number
  default     = 30
}

variable "lifecycle_rules" {
  description = "List of lifecycle management rules for blob storage"
  type = list(object({
    name                 = string
    enabled              = optional(bool, true)
    blob_types           = optional(list(string), ["blockBlob"])
    prefix_match         = optional(list(string), [])
    tier_to_cool_days    = optional(number, null)
    tier_to_archive_days = optional(number, null)
    delete_after_days    = optional(number, null)
    snapshot_delete_days = optional(number, null)
  }))
  default = []
}

variable "network_rules" {
  description = "Network rules for the storage account (default_action, bypass, ip_rules, virtual_network_subnet_ids)"
  type = object({
    default_action             = string
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}

variable "cmk_key_vault_key_id" {
  description = "Key Vault key ID for customer-managed encryption key (null to use Microsoft-managed keys)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
