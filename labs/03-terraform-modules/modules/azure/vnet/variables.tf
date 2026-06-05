# ============================================================
# VNet Module — Variables
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

variable "address_space" {
  description = "List of address spaces for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnets" {
  description = "Map of subnet configurations (address_prefix, service_endpoints, delegation)"
  type = map(object({
    address_prefix    = string
    service_endpoints = optional(list(string), [])
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = optional(list(string), [])
    }), null)
  }))
  default = {
    public = {
      address_prefix    = "10.0.1.0/24"
      service_endpoints = []
    }
    private = {
      address_prefix    = "10.0.2.0/24"
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
    }
    database = {
      address_prefix    = "10.0.3.0/24"
      service_endpoints = ["Microsoft.Sql"]
    }
    aks = {
      address_prefix    = "10.0.4.0/22"
      service_endpoints = ["Microsoft.ContainerRegistry"]
    }
  }
}

variable "enable_ddos" {
  description = "Enable Azure DDoS Protection Plan for the VNet"
  type        = bool
  default     = false
}

variable "vnet_peerings" {
  description = "Map of VNet peering configurations"
  type = map(object({
    remote_vnet_id          = string
    allow_vnet_access       = optional(bool, true)
    allow_forwarded_traffic = optional(bool, false)
    allow_gateway_transit   = optional(bool, false)
    use_remote_gateways     = optional(bool, false)
  }))
  default = {}
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}
