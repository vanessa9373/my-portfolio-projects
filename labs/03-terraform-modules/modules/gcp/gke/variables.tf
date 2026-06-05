# ============================================================
# GKE Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
}

variable "project_id" {
  description = "GCP project ID where the GKE cluster will be created"
  type        = string
}

variable "region" {
  description = "GCP region for the regional GKE cluster"
  type        = string
  default     = "us-central1"
}

variable "network" {
  description = "VPC network self-link or name for the GKE cluster"
  type        = string
}

variable "subnetwork" {
  description = "Subnet self-link or name for the GKE cluster nodes"
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary IP range in the subnet for GKE pods"
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary IP range in the subnet for GKE services"
  type        = string
}

variable "master_cidr" {
  description = "CIDR block for the GKE master nodes (must be /28)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "kubernetes_version" {
  description = "Minimum Kubernetes version for the master; null to use release channel default"
  type        = string
  default     = null
}

variable "release_channel" {
  description = "Release channel for GKE cluster upgrades: REGULAR, RAPID, or STABLE"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["REGULAR", "RAPID", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "release_channel must be one of: REGULAR, RAPID, STABLE, UNSPECIFIED."
  }
}

variable "node_pools" {
  description = "List of node pool configurations for the GKE cluster"
  type = list(object({
    name         = string
    machine_type = string
    min_count    = number
    max_count    = number
    disk_size    = number
    preemptible  = bool
    labels       = map(string)
    network_tags = optional(list(string), [])
  }))
  default = [
    {
      name         = "system"
      machine_type = "e2-standard-4"
      min_count    = 1
      max_count    = 3
      disk_size    = 100
      preemptible  = false
      labels       = { role = "system" }
      network_tags = []
    }
  ]
}

variable "enable_private_nodes" {
  description = "Enable private nodes so they have no external IP addresses"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable Calico network policy enforcement on the cluster"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for deploy-time security"
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the Kubernetes master"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "tags" {
  description = "Labels to apply to the GKE cluster and node pools"
  type        = map(string)
  default     = {}
}
