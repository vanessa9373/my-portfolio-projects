resource "aws_route53_health_check" "primary" {
  fqdn              = "api.us-east-1.ecommerce.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = {
    Name        = "primary-health-check"
    Environment = "production"
  }
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = "api.eu-west-1.ecommerce.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 10

  tags = {
    Name        = "secondary-health-check"
    Environment = "production"
  }
}

resource "aws_route53_record" "api_primary" {
  zone_id = var.zone_id
  name    = "api.ecommerce.example.com"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_alb_dns
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id
}

resource "aws_route53_record" "api_secondary" {
  zone_id = var.zone_id
  name    = "api.ecommerce.example.com"
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = true
  }

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id
}
