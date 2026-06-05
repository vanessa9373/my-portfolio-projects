# ============================================================
# Cloud SQL Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where the Cloud SQL instance will be created"
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud SQL instance"
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "Database engine and version (e.g., POSTGRES_15, MYSQL_8_0)"
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "Machine type for the Cloud SQL instance (e.g., db-custom-2-8192)"
  type        = string
  default     = "db-custom-2-8192"
}

variable "disk_size" {
  description = "Initial disk size in GB for the database instance"
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "Disk type for the database instance: PD_SSD or PD_HDD"
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "availability_type" {
  description = "Availability type: REGIONAL for HA or ZONAL for single zone"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "enable_private_ip" {
  description = "Enable private IP and disable public IP for the instance"
  type        = bool
  default     = true
}

variable "network" {
  description = "VPC network self-link for private IP connectivity"
  type        = string
  default     = null
}

variable "authorized_networks" {
  description = "List of authorized networks allowed to connect (public IP only)"
  type = list(object({
    name = string
    cidr = string
  }))
  default = []
}

variable "backup_enabled" {
  description = "Enable automated daily backups"
  type        = bool
  default     = true
}

variable "pitr_enabled" {
  description = "Enable Point-in-Time Recovery using transaction logs"
  type        = bool
  default     = true
}

variable "read_replica_count" {
  description = "Number of read replicas to create"
  type        = number
  default     = 0
}

variable "database_flags" {
  description = "List of database flags to set on the instance"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "maintenance_window" {
  description = "Preferred maintenance window configuration"
  type = object({
    day  = number
    hour = number
  })
  default = {
    day  = 7
    hour = 3
  }
}

variable "kms_key_name" {
  description = "Cloud KMS key name for CMEK encryption (null for Google-managed)"
  type        = string
  default     = null
}

variable "enable_insights" {
  description = "Enable Query Insights for performance monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Labels to apply to all Cloud SQL resources"
  type        = map(string)
  default     = {}
}
