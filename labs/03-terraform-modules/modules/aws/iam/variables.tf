# ============================================================
# IAM Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "role_name" {
  description = "Name suffix for the IAM role (combined with project_name)"
  type        = string
}

variable "service_principals" {
  description = "List of AWS service principals for the assume role policy (e.g., ec2.amazonaws.com)"
  type        = list(string)
  default     = []
}

variable "managed_policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "JSON-encoded inline policy document to attach to the role"
  type        = string
  default     = null
}

variable "create_instance_profile" {
  description = "Whether to create an IAM instance profile for EC2"
  type        = bool
  default     = false
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for EKS IRSA (overrides service_principals)"
  type        = string
  default     = null
}

variable "oidc_conditions" {
  description = "Map of OIDC conditions for the assume role policy (e.g., sub claim mappings)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
