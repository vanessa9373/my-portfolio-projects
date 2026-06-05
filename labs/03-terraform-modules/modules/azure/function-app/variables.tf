# ============================================================
# Azure Function App Module — Variables
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

variable "storage_account_name" {
  description = "Storage account name for function app"
  type        = string
}

variable "storage_account_access_key" {
  description = "Storage account access key"
  type        = string
  sensitive   = true
}

variable "service_plan_id" {
  description = "App Service Plan ID"
  type        = string
}

variable "runtime_stack" {
  description = "Runtime stack (node, python, java, dotnet)"
  type        = string
  default     = "node"
}

variable "runtime_version" {
  description = "Runtime version"
  type        = string
  default     = "18"
}

variable "always_on" {
  description = "Keep function app always on (requires non-Consumption plan)"
  type        = bool
  default     = false
}

variable "app_settings" {
  description = "Application settings / environment variables"
  type        = map(string)
  default     = {}
}

variable "connection_strings" {
  description = "Connection strings for the function app"
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default = []
}

variable "vnet_subnet_id" {
  description = "Subnet ID for VNet integration"
  type        = string
  default     = null
}

variable "enable_app_insights" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
