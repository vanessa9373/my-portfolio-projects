# ============================================================
# SQL Database Module — Variables
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

variable "administrator_login" {
  description = "SQL Server administrator login username"
  type        = string
}

variable "administrator_password" {
  description = "SQL Server administrator login password"
  type        = string
  sensitive   = true
}

variable "sku_name" {
  description = "SKU name for the SQL database (e.g., S0, S1, P1, GP_S_Gen5_2, BC_Gen5_4)"
  type        = string
  default     = "S1"
}

variable "max_size_gb" {
  description = "Maximum size of the database in gigabytes"
  type        = number
  default     = 50
}

variable "collation" {
  description = "Database collation setting"
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "zone_redundant" {
  description = "Enable zone redundancy for the database"
  type        = bool
  default     = false
}

variable "azuread_admin" {
  description = "Azure AD administrator configuration (login_username, object_id, tenant_id)"
  type = object({
    login_username = string
    object_id      = string
    tenant_id      = optional(string, null)
  })
  default = null
}

variable "firewall_rules" {
  description = "List of firewall rules to create on the SQL Server"
  type = list(object({
    name             = string
    start_ip_address = string
    end_ip_address   = string
  }))
  default = []
}

variable "enable_auditing" {
  description = "Enable extended auditing on the SQL Server"
  type        = bool
  default     = true
}

variable "storage_account_primary_blob_endpoint" {
  description = "Primary blob endpoint of the storage account used for auditing"
  type        = string
  default     = null
}

variable "storage_account_access_key" {
  description = "Access key for the storage account used for auditing"
  type        = string
  sensitive   = true
  default     = null
}

variable "audit_retention_days" {
  description = "Number of days to retain audit logs"
  type        = number
  default     = 90
}

variable "enable_geo_replication" {
  description = "Enable geo-replication for the SQL database"
  type        = bool
  default     = false
}

variable "geo_location" {
  description = "Azure region for the geo-replicated secondary server"
  type        = string
  default     = "westus2"
}

variable "subnet_id" {
  description = "Subnet ID for the private endpoint (null to skip private endpoint)"
  type        = string
  default     = null
}

variable "ltr_weekly_retention" {
  description = "Long-term backup retention period for weekly backups (ISO 8601)"
  type        = string
  default     = "P4W"
}

variable "ltr_monthly_retention" {
  description = "Long-term backup retention period for monthly backups (ISO 8601)"
  type        = string
  default     = "P12M"
}

variable "ltr_yearly_retention" {
  description = "Long-term backup retention period for yearly backups (ISO 8601)"
  type        = string
  default     = "P5Y"
}

variable "ltr_week_of_year" {
  description = "Week of the year for the yearly long-term retention backup"
  type        = number
  default     = 1
}

variable "short_term_retention_days" {
  description = "Number of days for short-term point-in-time restore retention"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
