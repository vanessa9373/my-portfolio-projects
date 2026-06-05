# ============================================================
# NSG Module — Variables
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

variable "nsg_name" {
  description = "Custom name for the NSG (defaults to project_name-nsg if null)"
  type        = string
  default     = null
}

variable "inbound_rules" {
  description = "List of custom inbound security rules"
  type = list(object({
    name                         = string
    priority                     = number
    access                       = string
    protocol                     = string
    source_port_range            = optional(string, "*")
    destination_port_range       = optional(string, null)
    destination_port_ranges      = optional(list(string), null)
    source_address_prefix        = optional(string, null)
    source_address_prefixes      = optional(list(string), null)
    destination_address_prefix   = optional(string, "*")
  }))
  default = []
}

variable "outbound_rules" {
  description = "List of custom outbound security rules"
  type = list(object({
    name                           = string
    priority                       = number
    access                         = string
    protocol                       = string
    source_port_range              = optional(string, "*")
    destination_port_range         = optional(string, null)
    destination_port_ranges        = optional(list(string), null)
    source_address_prefix          = optional(string, "*")
    destination_address_prefix     = optional(string, null)
    destination_address_prefixes   = optional(list(string), null)
  }))
  default = []
}

# --- Preset toggles ---
variable "preset_web" {
  description = "Enable preset rules for HTTP (80) and HTTPS (443) inbound traffic"
  type        = bool
  default     = false
}

variable "preset_ssh" {
  description = "Enable preset rule for SSH (22) inbound traffic"
  type        = bool
  default     = false
}

variable "preset_rdp" {
  description = "Enable preset rule for RDP (3389) inbound traffic"
  type        = bool
  default     = false
}

variable "preset_database" {
  description = "Enable preset rule for common database ports (1433, 3306, 5432)"
  type        = bool
  default     = false
}

variable "ssh_source_address" {
  description = "Source address prefix for the SSH preset rule"
  type        = string
  default     = "*"
}

variable "rdp_source_address" {
  description = "Source address prefix for the RDP preset rule"
  type        = string
  default     = "*"
}

variable "database_source_address" {
  description = "Source address prefix for the database preset rule"
  type        = string
  default     = "VirtualNetwork"
}

variable "subnet_ids" {
  description = "List of subnet IDs to associate with this NSG"
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Enable NSG flow logs"
  type        = bool
  default     = false
}

variable "storage_account_id" {
  description = "Storage account ID for NSG flow logs"
  type        = string
  default     = null
}

variable "network_watcher_name" {
  description = "Name of the Network Watcher for flow logs"
  type        = string
  default     = null
}

variable "network_watcher_resource_group" {
  description = "Resource group of the Network Watcher for flow logs"
  type        = string
  default     = null
}

variable "flow_log_retention_days" {
  description = "Number of days to retain flow logs"
  type        = number
  default     = 90
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for traffic analytics"
  type        = string
  default     = null
}

variable "log_analytics_workspace_guid" {
  description = "Log Analytics workspace GUID for traffic analytics"
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
