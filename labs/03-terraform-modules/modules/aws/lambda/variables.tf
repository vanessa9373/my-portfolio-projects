# ============================================================
# Lambda Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "function_name" {
  description = "Name suffix for the Lambda function (combined with project_name)"
  type        = string
}

variable "runtime" {
  description = "Lambda function runtime (e.g., python3.12, nodejs20.x)"
  type        = string
  default     = "python3.12"
}

variable "handler" {
  description = "Lambda function handler (e.g., index.handler)"
  type        = string
  default     = "index.handler"
}

variable "filename" {
  description = "Path to the Lambda deployment package ZIP file"
  type        = string
}

variable "memory_size" {
  description = "Amount of memory in MB allocated to the Lambda function"
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Timeout in seconds for the Lambda function"
  type        = number
  default     = 30
}

variable "environment_variables" {
  description = "Map of environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "vpc_config" {
  description = "VPC configuration for the Lambda function (null to run outside VPC)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "event_sources" {
  description = "List of event source mappings (SQS, DynamoDB streams, Kinesis streams)"
  type = list(object({
    event_source_arn  = string
    batch_size        = optional(number, 10)
    enabled           = optional(bool, true)
    starting_position = optional(string)
  }))
  default = []
}

variable "enable_function_url" {
  description = "Whether to create a Lambda function URL"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
