variable "project_name"             { type = string }
variable "environment"              { type = string }
variable "vpc_cidr"                 { type = string }
variable "availability_zones"       { type = list(string) }
variable "public_subnet_cidrs"      { type = list(string) }
variable "private_subnet_cidrs"     { type = list(string) }
variable "database_subnet_cidrs"    { type = list(string) }
variable "endpoint_security_group_id" {
  type    = string
  default = ""
}
