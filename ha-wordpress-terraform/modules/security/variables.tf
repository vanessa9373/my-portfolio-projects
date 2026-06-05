variable "project_name" { type = string }
variable "environment"  { type = string }
variable "vpc_id"       { type = string }
variable "vpc_cidr"     { type = string }
variable "account_id"   { type = string }
variable "domain_name"  { type = string; default = "" }
