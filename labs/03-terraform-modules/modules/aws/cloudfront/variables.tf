# ============================================================
# CloudFront Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "origin_domain_name" {
  description = "Domain name of the origin (S3 bucket regional domain or ALB DNS)"
  type        = string
}

variable "origin_type" {
  description = "Type of origin: s3 or alb"
  type        = string
  default     = "s3"

  validation {
    condition     = contains(["s3", "alb"], var.origin_type)
    error_message = "origin_type must be either 's3' or 'alb'."
  }
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 origin bucket (required when origin_type is s3)"
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS (must be in us-east-1)"
  type        = string
  default     = null
}

variable "domain_aliases" {
  description = "List of custom domain aliases for the distribution"
  type        = list(string)
  default     = []
}

variable "default_root_object" {
  description = "Default root object for the distribution"
  type        = string
  default     = "index.html"
}

variable "waf_web_acl_id" {
  description = "WAF Web ACL ID to associate with the distribution"
  type        = string
  default     = null
}

variable "geo_restriction" {
  description = "Geo restriction configuration for the distribution"
  type = object({
    restriction_type = string
    locations        = list(string)
  })
  default = {
    restriction_type = "none"
    locations        = []
  }
}

variable "custom_error_responses" {
  description = "Custom error responses (e.g., for SPA 403 -> index.html)"
  type = list(object({
    error_code            = number
    response_code         = number
    response_page_path    = string
    error_caching_min_ttl = number
  }))
  default = [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10
    }
  ]
}

variable "logging_bucket" {
  description = "S3 bucket domain name for CloudFront access logs (null to disable)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
