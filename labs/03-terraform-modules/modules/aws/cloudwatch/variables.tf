# ============================================================
# CloudWatch Module — Variables
# Author: Jenella Awo
# ============================================================

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
}

variable "log_group_name" {
  description = "Name suffix for the CloudWatch log group"
  type        = string
}

variable "retention_in_days" {
  description = "Number of days to retain log events"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "ARN of KMS key for log group encryption (null for no encryption)"
  type        = string
  default     = null
}

variable "alarms" {
  description = "List of CloudWatch metric alarm configurations"
  type = list(object({
    name                = string
    metric_name         = string
    namespace           = string
    statistic           = string
    threshold           = number
    comparison_operator = string
    period              = number
    evaluation_periods  = number
  }))
  default = []
}

variable "dashboard_widgets" {
  description = "List of CloudWatch dashboard widget configurations"
  type = list(object({
    type    = string
    x       = number
    y       = number
    width   = number
    height  = number
    title   = string
    metrics = list(list(string))
    region  = string
    period  = number
    stat    = string
  }))
  default = []
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
