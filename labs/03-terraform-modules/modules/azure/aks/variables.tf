# ============================================================
# AKS Module — Variables
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

variable "kubernetes_version" {
  description = "Version of Kubernetes to deploy"
  type        = string
  default     = "1.29"
}

variable "vnet_subnet_id" {
  description = "Subnet ID for the AKS node pools (Azure CNI)"
  type        = string
}

variable "system_node_count" {
  description = "Number of nodes in the system node pool (used when auto-scaling is disabled)"
  type        = number
  default     = 3
}

variable "system_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "user_node_pools" {
  description = "List of user node pool configurations"
  type = list(object({
    name               = string
    vm_size            = string
    node_count         = optional(number, 2)
    enable_auto_scaling = optional(bool, false)
    min_count          = optional(number, 1)
    max_count          = optional(number, 5)
    os_disk_size_gb    = optional(number, 128)
    max_pods           = optional(number, 30)
    mode               = optional(string, "User")
    os_type            = optional(string, "Linux")
    zones              = optional(list(string), null)
    labels             = optional(map(string), {})
    taints             = optional(list(string), [])
  }))
  default = []
}

variable "enable_auto_scaling" {
  description = "Enable cluster auto-scaler for the system node pool"
  type        = bool
  default     = true
}

variable "min_count" {
  description = "Minimum node count for auto-scaler (system pool)"
  type        = number
  default     = 2
}

variable "max_count" {
  description = "Maximum node count for auto-scaler (system pool)"
  type        = number
  default     = 10
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB for the system node pool"
  type        = number
  default     = 128
}

variable "max_pods" {
  description = "Maximum number of pods per node"
  type        = number
  default     = 30
}

variable "availability_zones" {
  description = "Availability zones for the system node pool"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "private_cluster" {
  description = "Enable private cluster (API server accessible only within VNet)"
  type        = bool
  default     = false
}

variable "sku_tier" {
  description = "AKS SKU tier (Free or Standard)"
  type        = string
  default     = "Standard"
}

variable "network_policy" {
  description = "Network policy provider (azure or calico)"
  type        = string
  default     = "azure"
}

variable "service_cidr" {
  description = "CIDR range for Kubernetes services"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within the service CIDR for the DNS service"
  type        = string
  default     = "172.16.0.10"
}

variable "enable_azure_ad_rbac" {
  description = "Enable Azure AD RBAC integration"
  type        = bool
  default     = true
}

variable "tenant_id" {
  description = "Azure AD tenant ID for RBAC integration"
  type        = string
  default     = null
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy add-on for AKS"
  type        = bool
  default     = true
}

variable "enable_key_vault_secrets_provider" {
  description = "Enable the Key Vault secrets provider CSI driver"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Container Insights monitoring"
  type        = string
  default     = null
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
