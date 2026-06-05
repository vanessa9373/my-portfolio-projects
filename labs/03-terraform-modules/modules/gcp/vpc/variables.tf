# ============================================================
# VPC Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "Default GCP region for the router and NAT gateway"
  type        = string
  default     = "us-central1"
}

variable "subnets" {
  description = "List of subnet configurations including secondary ranges for GKE"
  type = list(object({
    name   = string
    cidr   = string
    region = string
    secondary_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
  }))
}

variable "enable_nat" {
  description = "Enable Cloud NAT for private instances to reach the internet"
  type        = bool
  default     = true
}

variable "firewall_rules" {
  description = "List of firewall rule configurations for ingress and egress"
  type = list(object({
    name               = string
    description        = optional(string, "Managed by Terraform")
    direction          = optional(string, "INGRESS")
    priority           = optional(number, 1000)
    source_ranges      = optional(list(string), [])
    destination_ranges = optional(list(string), [])
    source_tags        = optional(list(string))
    target_tags        = optional(list(string))
    allow = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
    deny = optional(list(object({
      protocol = string
      ports    = optional(list(string))
    })), [])
  }))
  default = []
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs on all subnets for network monitoring"
  type        = bool
  default     = true
}

variable "enable_shared_vpc" {
  description = "Enable Shared VPC host project configuration"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Labels to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
