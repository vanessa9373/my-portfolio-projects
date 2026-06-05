# ============================================================
# Azure DNS Module — Variables
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

variable "domain_name" {
  description = "Domain name for the DNS zone"
  type        = string
}

variable "private_zone" {
  description = "Create a private DNS zone instead of public"
  type        = bool
  default     = false
}

variable "vnet_id" {
  description = "VNet ID for private DNS zone link"
  type        = string
  default     = null
}

variable "enable_auto_registration" {
  description = "Enable auto-registration for private DNS zone"
  type        = bool
  default     = false
}

variable "records" {
  description = "List of DNS records to create"
  type = list(object({
    name   = string
    type   = string
    ttl    = number
    values = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
