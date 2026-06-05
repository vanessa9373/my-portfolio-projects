variable "name_prefix"      { type = string }
variable "vpc_id"           { type = string }
variable "isolated_subnets" { type = list(string) }
variable "allowed_sg_ids"   { type = list(string) }
variable "instance_class"   { type = string; default = "db.t3.medium" }
variable "database_name"    { type = string; default = "nexashop" }
