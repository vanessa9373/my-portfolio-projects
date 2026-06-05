variable "name_prefix"    { type = string }
variable "domain_name"    { type = string }
variable "callback_urls"  { type = list(string); default = [] }
variable "logout_urls"    { type = list(string); default = [] }
