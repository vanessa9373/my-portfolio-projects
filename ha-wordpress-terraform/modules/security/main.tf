locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── KMS KEY — encrypt RDS, EBS, Secrets Manager ──────────────────────────────

resource "aws_kms_key" "main" {
  description             = "${local.name_prefix} encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM root permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow RDS and EBS to use this key"
        Effect = "Allow"
        Principal = {
          Service = ["rds.amazonaws.com", "ec2.amazonaws.com"]
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${local.name_prefix}-kms-key" }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.main.key_id
}

# ─── ACM CERTIFICATE (us-east-1 required for CloudFront) ─────────────────────

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle { create_before_destroy = true }
  tags = { Name = "${local.name_prefix}-acm-cert" }
}

# ─── SECURITY GROUPS ──────────────────────────────────────────────────────────

# ALB — accept HTTPS from internet, HTTP redirects to HTTPS
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: accept 443 from internet, 80 for redirect"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# EC2 WordPress — only accept traffic from ALB
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "WordPress EC2: accept HTTP only from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (NAT GW for updates/patches)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ec2-sg" }
}

# RDS — only accept MySQL traffic from EC2
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS: accept MySQL only from WordPress EC2"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from WordPress EC2 only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# VPC Endpoints — SSM, Secrets Manager
resource "aws_security_group" "endpoints" {
  name        = "${local.name_prefix}-endpoints-sg"
  description = "VPC Endpoints: accept HTTPS from VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${local.name_prefix}-endpoints-sg" }
}

# ─── WAF WebACL — attached to CloudFront ─────────────────────────────────────

resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name_prefix}-waf"
  description = "WordPress WAF: block OWASP top 10, rate limit, geo-block"
  scope       = "CLOUDFRONT"

  default_action { allow {} }

  # AWS Managed — OWASP Common Ruleset
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed — Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed — SQL Injection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting — block IPs making > 2000 req/5 min (DDoS protection)
  rule {
    name     = "RateLimitRule"
    priority = 4
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.name_prefix}-waf" }
}

# ─── IAM: EC2 INSTANCE ROLE (least privilege) ─────────────────────────────────

resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_s3" {
  name = "s3-media-access"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-${var.environment}-media",
          "arn:aws:s3:::${var.project_name}-${var.environment}-media/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:${var.account_id}:secret:${local.name_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# SSM Session Manager — no bastion host needed
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}
