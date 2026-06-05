variable "project_name"  { type = string }
variable "environment"   { type = string }
variable "alb_arn_suffix" { type = string }
variable "tg_arn_suffix"  { type = string; default = "" }
variable "asg_name"       { type = string }
variable "db_identifier"  { type = string }
variable "alert_email"    { type = string }
variable "account_id"     { type = string }
variable "region"         { type = string }
