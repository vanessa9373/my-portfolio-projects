locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── APPLICATION LOAD BALANCER ────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  # Enable deletion protection in production
  enable_deletion_protection = var.environment == "prod" ? true : false

  # Access logs to S3
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${local.name_prefix}-alb-logs-${var.account_id}"
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::127311923021:root" }  # ELB service account us-east-1
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/${var.account_id}/*"
    }]
  })
}

# Target Group — EC2 WordPress instances
resource "aws_lb_target_group" "wordpress" {
  name     = "${local.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 10
    interval            = 30
    path                = "/wp-login.php"
    matcher             = "200,301"
  }

  deregistration_delay = 30  # Drain connections before removing instance

  tags = { Name = "${local.name_prefix}-tg" }
}

# HTTP → HTTPS redirect listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener with ACM cert
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# ─── LAUNCH TEMPLATE ──────────────────────────────────────────────────────────

resource "aws_launch_template" "wordpress" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  key_name = var.key_name != "" ? var.key_name : null

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_security_group_id]
    delete_on_termination       = true
  }

  # EBS root volume — encrypted with KMS
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only — prevents SSRF attacks
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }  # Detailed CloudWatch monitoring

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install required packages
    dnf update -y
    dnf install -y httpd php php-mysqlnd php-fpm php-json php-gd \
      php-mbstring php-xml amazon-cloudwatch-agent amazon-ssm-agent

    # Fetch database credentials from Secrets Manager
    DB_SECRET=$(aws secretsmanager get-secret-value \
      --secret-id ${var.db_secret_arn} \
      --query SecretString --output text)
    DB_PASS=$(echo $DB_SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

    # Download and configure WordPress
    cd /var/www/html
    wget -q https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz --strip-components=1
    rm latest.tar.gz

    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/${var.db_name}/"    wp-config.php
    sed -i "s/username_here/${var.db_username}/"     wp-config.php
    sed -i "s/password_here/$DB_PASS/"               wp-config.php
    sed -i "s/localhost/${var.db_host}/"             wp-config.php

    # Use S3 for media uploads (WP Offload Media pattern)
    echo "define('AS3CF_SETTINGS', serialize(array('provider' => 'aws', 'bucket' => '${var.s3_bucket_name}')));" >> wp-config.php

    # Fix permissions
    chown -R apache:apache /var/www/html
    chmod -R 755 /var/www/html

    # Apache config
    sed -i 's/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
    systemctl enable --now httpd

    # CloudWatch Agent config
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              { "file_path": "/var/log/httpd/access_log", "log_group_name": "/aws/ec2/${local.name_prefix}/apache/access" },
              { "file_path": "/var/log/httpd/error_log",  "log_group_name": "/aws/ec2/${local.name_prefix}/apache/error" },
              { "file_path": "/var/log/messages",          "log_group_name": "/aws/ec2/${local.name_prefix}/system" }
            ]
          }
        }
      },
      "metrics": {
        "metrics_collected": {
          "mem":  { "measurement": ["mem_used_percent"] },
          "disk": { "measurement": ["disk_used_percent"], "resources": ["/"] }
        }
      }
    }
    CWCONFIG
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
  EOF
  )

  lifecycle { create_before_destroy = true }

  tags = { Name = "${local.name_prefix}-lt" }
}

# ─── AUTO SCALING GROUP ───────────────────────────────────────────────────────

resource "aws_autoscaling_group" "wordpress" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.wordpress.arn]
  health_check_type   = "ELB"  # Use ALB health checks, not just EC2 status
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  # Instance refresh — zero-downtime deployments
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-wordpress"
    propagate_at_launch = true
  }

  lifecycle { create_before_destroy = true }
}

# ─── AUTO SCALING POLICIES ────────────────────────────────────────────────────

# Target tracking — maintain 70% average CPU across the ASG
resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "${local.name_prefix}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = 70.0
    disable_scale_in = false
  }
}

# Request count tracking — maintain 1000 req/instance
resource "aws_autoscaling_policy" "request_tracking" {
  name                   = "${local.name_prefix}-request-tracking"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.wordpress.arn_suffix}"
    }
    target_value = 1000
  }
}

# Scheduled scaling — pre-warm before expected traffic spike
resource "aws_autoscaling_schedule" "business_hours_scale_out" {
  scheduled_action_name  = "business-hours-scale-out"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  min_size               = 4
  max_size               = 10
  desired_capacity       = 4
  recurrence             = "0 8 * * MON-FRI"  # 8am UTC weekdays
  time_zone              = "UTC"
}

resource "aws_autoscaling_schedule" "off_hours_scale_in" {
  scheduled_action_name  = "off-hours-scale-in"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  min_size               = 2
  max_size               = 10
  desired_capacity       = 2
  recurrence             = "0 20 * * MON-FRI"  # 8pm UTC weekdays
  time_zone              = "UTC"
}
