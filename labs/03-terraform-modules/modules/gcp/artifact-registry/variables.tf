# ============================================================
# Artifact Registry Module — Variables
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

variable "repository_name" {
  description = "Name of the repository"
  type        = string
  default     = "docker"
}

variable "format" {
  description = "Repository format (DOCKER, MAVEN, NPM, PYTHON, GO)"
  type        = string
  default     = "DOCKER"

  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "GO", "APT", "YUM"], var.format)
    error_message = "Format must be one of: DOCKER, MAVEN, NPM, PYTHON, GO, APT, YUM."
  }
}

variable "description" {
  description = "Repository description"
  type        = string
  default     = "Managed by Terraform"
}

variable "kms_key_name" {
  description = "KMS key for encryption (CMEK). Null uses Google-managed keys."
  type        = string
  default     = null
}

variable "cleanup_policies" {
  description = "Cleanup policies for the repository"
  type        = list(any)
  default     = []
}

variable "iam_members" {
  description = "IAM member bindings for the repository"
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

variable "tags" {
  description = "Labels to apply to the repository"
  type        = map(string)
  default     = {}
}
