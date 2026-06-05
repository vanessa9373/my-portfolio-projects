# ============================================================
# Cloud DNS Module — Variables
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

variable "domain_name" {
  description = "Domain name for the DNS zone (without trailing dot)"
  type        = string
}

variable "private_zone" {
  description = "Create a private DNS zone"
  type        = bool
  default     = false
}

variable "network" {
  description = "VPC network self_link for private DNS zone"
  type        = string
  default     = null
}

variable "enable_dnssec" {
  description = "Enable DNSSEC for public zones"
  type        = bool
  default     = false
}

variable "records" {
  description = "DNS records to create"
  type = list(object({
    name    = string
    type    = string
    ttl     = number
    rrdatas = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
