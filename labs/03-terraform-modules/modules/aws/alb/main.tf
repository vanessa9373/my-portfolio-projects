# ============================================================
# ALB Module — Application Load Balancer with Security Group,
# HTTP/HTTPS Listeners, Target Groups, and Access Logs
# Author: Jenella Awo
# ============================================================

locals {
  alb_name = "${var.project_name}-alb"
}

# ----------------------------------------------
# Security Group for ALB
# ----------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.alb_name}-sg"
  description = "Security group for ${local.alb_name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.alb_name}-sg"
  })
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP inbound"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidrs
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS inbound"
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound traffic"
}

# ----------------------------------------------
# Application Load Balancer
# ----------------------------------------------
resource "aws_lb" "this" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "alb-logs/${var.project_name}"
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = local.alb_name
  })
}

# ----------------------------------------------
# Default Target Group
# ----------------------------------------------
resource "aws_lb_target_group" "default" {
  name        = "${var.project_name}-tg-default"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = var.target_type

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-tg-default"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------
# HTTP Listener (redirect to HTTPS)
# ----------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
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

  tags = merge(var.tags, {
    Name = "${var.project_name}-http-listener"
  })
}

# ----------------------------------------------
# HTTPS Listener with ACM Certificate
# ----------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-https-listener"
  })
}
