# ============================================================
# Memorystore Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "instance_name" {
  description = "Name suffix for the Redis instance"
  type        = string
  default     = "redis"
}

variable "tier" {
  description = "Service tier (BASIC or STANDARD_HA)"
  type        = string
  default     = "STANDARD_HA"

  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.tier)
    error_message = "Tier must be BASIC or STANDARD_HA."
  }
}

variable "memory_size_gb" {
  description = "Memory size in GB"
  type        = number
  default     = 1
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "REDIS_7_0"
}

variable "authorized_network" {
  description = "VPC network self_link for the Redis instance"
  type        = string
}

variable "reserved_ip_range" {
  description = "Reserved IP range for the Redis instance"
  type        = string
  default     = null
}

variable "auth_enabled" {
  description = "Enable AUTH for the Redis instance"
  type        = bool
  default     = true
}

variable "transit_encryption" {
  description = "Enable in-transit encryption (TLS)"
  type        = bool
  default     = true
}

variable "redis_configs" {
  description = "Redis configuration parameters"
  type        = map(string)
  default = {
    maxmemory-policy = "volatile-lru"
  }
}

variable "maintenance_window" {
  description = "Maintenance window configuration"
  type = object({
    day  = string
    hour = number
  })
  default = null
}

variable "tags" {
  description = "Labels to apply to the instance"
  type        = map(string)
  default     = {}
}
