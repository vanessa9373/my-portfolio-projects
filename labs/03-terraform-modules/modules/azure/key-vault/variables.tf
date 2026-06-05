# ============================================================
# Key Vault Module — Variables
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

variable "sku_name" {
  description = "SKU for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"
}

variable "tenant_id" {
  description = "Azure AD tenant ID for the Key Vault (defaults to current client config)"
  type        = string
  default     = null
}

variable "access_policies" {
  description = "List of access policy configurations (ignored when RBAC is enabled)"
  type = list(object({
    tenant_id               = optional(string, null)
    object_id               = string
    key_permissions         = optional(list(string), [])
    secret_permissions      = optional(list(string), [])
    certificate_permissions = optional(list(string), [])
    storage_permissions     = optional(list(string), [])
  }))
  default = []
}

variable "enable_rbac" {
  description = "Enable RBAC authorization instead of access policies"
  type        = bool
  default     = false
}

variable "network_acls" {
  description = "Network ACL configuration for the Key Vault"
  type = object({
    default_action             = string
    bypass                     = optional(string, "AzureServices")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted vaults and vault objects (7-90)"
  type        = number
  default     = 90
}

variable "enable_purge_protection" {
  description = "Enable purge protection to prevent permanent deletion during retention period"
  type        = bool
  default     = true
}

variable "enabled_for_deployment" {
  description = "Allow Azure VMs to retrieve certificates stored as secrets"
  type        = bool
  default     = false
}

variable "enabled_for_disk_encryption" {
  description = "Allow Azure Disk Encryption to retrieve secrets and unwrap keys"
  type        = bool
  default     = true
}

variable "enabled_for_template_deployment" {
  description = "Allow Azure Resource Manager to retrieve secrets"
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "Subnet ID for the private endpoint (null to skip private endpoint)"
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings (null to skip)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
