locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── SNS TOPIC for ALERTS ─────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─── CLOUDWATCH ALARMS ────────────────────────────────────────────────────────

# ALB: 5xx error rate > 5%
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5

  metric_query {
    id          = "error_rate"
    expression  = "(m2/m1)*100"
    label       = "5xx Error Rate"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  metric_query {
    id = "m2"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  alarm_description = "5xx error rate > 5% on ALB"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  ok_actions        = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

# ALB: Target response time p99 > 2s
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-latency-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 2
  alarm_description   = "ALB p99 response time > 2s — WordPress performance degraded"

  metric_name = "TargetResponseTime"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "p99"
  dimensions  = { LoadBalancer = var.alb_arn_suffix }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

# ALB: Unhealthy host count > 0
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "One or more EC2 instances are unhealthy — ASG will replace them"

  metric_name = "UnHealthyHostCount"
  namespace   = "AWS/ApplicationELB"
  period      = 60
  statistic   = "Maximum"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ASG: CPU > 85% (scaling may be lagging)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 85
  alarm_description   = "ASG average CPU > 85% — scaling lag or undersized instances"

  metric_name = "CPUUtilization"
  namespace   = "AWS/EC2"
  period      = 60
  statistic   = "Average"
  dimensions  = { AutoScalingGroupName = var.asg_name }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
  treat_missing_data = "missing"
}

# RDS: CPU > 80%
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name_prefix}-rds-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 80
  alarm_description   = "RDS CPU > 80% — review slow queries, consider read replica"

  metric_name = "CPUUtilization"
  namespace   = "AWS/RDS"
  period      = 60
  statistic   = "Average"
  dimensions  = { DBInstanceIdentifier = var.db_identifier }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
  treat_missing_data = "missing"
}

# RDS: Free storage < 10 GB
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 10737418240  # 10 GB in bytes
  alarm_description   = "RDS free storage < 10 GB — storage autoscaling may be needed"

  metric_name = "FreeStorageSpace"
  namespace   = "AWS/RDS"
  period      = 300
  statistic   = "Minimum"
  dimensions  = { DBInstanceIdentifier = var.db_identifier }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# RDS: Connection count > 400 (near max_connections 500)
resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${local.name_prefix}-rds-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 400
  alarm_description   = "RDS connection count > 400 — near limit of 500, consider RDS Proxy"

  metric_name = "DatabaseConnections"
  namespace   = "AWS/RDS"
  period      = 60
  statistic   = "Maximum"
  dimensions  = { DBInstanceIdentifier = var.db_identifier }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ─── CLOUDWATCH DASHBOARD ─────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x = 0; y = 0; width = 24; height = 1
        properties = { markdown = "# ${local.name_prefix} — Operations Dashboard" }
      },
      {
        type = "metric"
        x = 0; y = 1; width = 12; height = 6
        properties = {
          title  = "ALB — Request Count & 5xx Errors"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type = "metric"
        x = 12; y = 1; width = 12; height = 6
        properties = {
          title  = "ALB — Target Response Time (p95, p99)"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99" }]
          ]
        }
      },
      {
        type = "metric"
        x = 0; y = 7; width = 12; height = 6
        properties = {
          title  = "EC2 ASG — CPU Utilization"
          period = 60
          stat   = "Average"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]]
        }
      },
      {
        type = "metric"
        x = 12; y = 7; width = 12; height = 6
        properties = {
          title  = "RDS — CPU & Connections"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier, { stat = "Average" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier, { yAxis = "right", stat = "Maximum" }]
          ]
        }
      }
    ]
  })
}
