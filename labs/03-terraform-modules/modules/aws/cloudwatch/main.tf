# ============================================================
# CloudWatch Module — Log Group, Metric Alarms, Dashboard,
# and SNS Notification Integration
# Author: Jenella Awo
# ============================================================

# ----------------------------------------------
# CloudWatch Log Group
# ----------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/app/${var.project_name}/${var.log_group_name}"
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.log_group_name}"
  })
}

# ----------------------------------------------
# Metric Alarms
# ----------------------------------------------
resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = { for idx, alarm in var.alarms : alarm.name => alarm }

  alarm_name          = "${var.project_name}-${each.value.name}"
  alarm_description   = "Alarm: ${each.value.name} for ${var.project_name}"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"

  # SNS actions
  alarm_actions             = var.sns_topic_arn != null ? [var.sns_topic_arn] : []
  ok_actions                = var.sns_topic_arn != null ? [var.sns_topic_arn] : []
  insufficient_data_actions = []

  tags = merge(var.tags, {
    Name = "${var.project_name}-${each.value.name}"
  })
}

# ----------------------------------------------
# CloudWatch Dashboard
# ----------------------------------------------
resource "aws_cloudwatch_dashboard" "this" {
  count          = length(var.dashboard_widgets) > 0 ? 1 : 0
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      for widget in var.dashboard_widgets : {
        type   = widget.type
        x      = widget.x
        y      = widget.y
        width  = widget.width
        height = widget.height
        properties = {
          title   = widget.title
          metrics = widget.metrics
          region  = widget.region
          period  = widget.period
          stat    = widget.stat
          view    = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}
