variable "project_name"           { type = string }
variable "environment"            { type = string }
variable "vpc_id"                 { type = string }
variable "public_subnet_ids"      { type = list(string) }
variable "private_subnet_ids"     { type = list(string) }
variable "alb_security_group_id"  { type = string }
variable "ec2_security_group_id"  { type = string }
variable "instance_type"          { type = string; default = "t3.medium" }
variable "min_size"               { type = number; default = 2 }
variable "max_size"               { type = number; default = 10 }
variable "desired_capacity"       { type = number; default = 2 }
variable "certificate_arn"        { type = string }
variable "db_host"                { type = string }
variable "db_name"                { type = string }
variable "db_username"            { type = string; default = "wpadmin" }
variable "db_secret_arn"          { type = string }
variable "s3_bucket_name"         { type = string }
variable "instance_profile_name"  { type = string; default = "" }
variable "kms_key_id"             { type = string; default = "" }
variable "key_name"               { type = string; default = "" }
variable "account_id"             { type = string }
