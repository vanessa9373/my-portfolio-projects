# ============================================================
# IAM Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as a prefix for the service account ID"
  type        = string
}

variable "project_id" {
  description = "GCP project ID for IAM resources"
  type        = string
}

variable "service_account_name" {
  description = "Suffix for the service account ID (prefixed with project_name)"
  type        = string
}

variable "display_name" {
  description = "Human-readable display name for the service account"
  type        = string
}

variable "roles" {
  description = "List of IAM roles to grant to the service account at project level"
  type        = list(string)
  default     = []
}

variable "workload_identity_namespace" {
  description = "Workload Identity namespace (PROJECT_ID.svc.id.goog) for GKE binding"
  type        = string
  default     = null
}

variable "workload_identity_sa" {
  description = "Kubernetes service account (namespace/sa-name) for Workload Identity"
  type        = string
  default     = "default/default"
}

variable "create_custom_role" {
  description = "Whether to create a custom IAM role with specified permissions"
  type        = bool
  default     = false
}

variable "custom_role_permissions" {
  description = "List of GCP permissions for the custom role"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Labels for reference (GCP service accounts do not support labels directly)"
  type        = map(string)
  default     = {}
}
