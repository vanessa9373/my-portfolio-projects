variable "project_name"         { type = string }
variable "environment"          { type = string }
variable "database_subnet_ids"  { type = list(string) }
variable "db_security_group_id" { type = string }
variable "db_name"              { type = string; default = "wordpress" }
variable "db_username"          { type = string; default = "wpadmin" }
variable "db_instance_class"    { type = string; default = "db.t3.medium" }
variable "multi_az"             { type = bool; default = true }
variable "deletion_protection"  { type = bool; default = true }
variable "backup_retention_days" { type = number; default = 30 }
variable "kms_key_id"           { type = string }
