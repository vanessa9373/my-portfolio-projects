variable "project_name"            { type = string }
variable "environment"             { type = string }
variable "alb_dns_name"            { type = string }
variable "alb_zone_id"             { type = string }
variable "domain_name"             { type = string; default = "" }
variable "certificate_arn"         { type = string }
variable "waf_acl_arn"             { type = string }
variable "kms_key_id"              { type = string; default = "" }
variable "account_id"              { type = string }
variable "cloudfront_header_secret" { type = string; default = "wp-cf-header-secret-2024" }
