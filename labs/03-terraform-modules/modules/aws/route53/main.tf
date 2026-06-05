# ============================================================
# Route53 Module — Hosted Zone with DNS Records,
# Health Checks, and Optional DNSSEC
# Author: Jenella Awo
# ============================================================

# ----------------------------------------------
# Hosted Zone
# ----------------------------------------------
resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "${var.project_name} hosted zone for ${var.domain_name}"

  # Private zone configuration
  dynamic "vpc" {
    for_each = var.private_zone && var.vpc_id != null ? [1] : []
    content {
      vpc_id = var.vpc_id
    }
  }

  force_destroy = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.domain_name}"
  })
}

# ----------------------------------------------
# DNS Records (non-alias)
# ----------------------------------------------
resource "aws_route53_record" "standard" {
  for_each = {
    for idx, record in var.records : "${record.name}-${record.type}" => record
    if record.alias == null
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}

# ----------------------------------------------
# DNS Records (alias)
# ----------------------------------------------
resource "aws_route53_record" "alias" {
  for_each = {
    for idx, record in var.records : "${record.name}-${record.type}" => record
    if record.alias != null
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = each.value.alias.name
    zone_id                = each.value.alias.zone_id
    evaluate_target_health = each.value.alias.evaluate_target_health
  }
}

# ----------------------------------------------
# Health Checks
# ----------------------------------------------
resource "aws_route53_health_check" "this" {
  for_each = { for idx, hc in var.health_checks : idx => hc }

  fqdn              = each.value.fqdn
  port               = each.value.port
  type               = each.value.type
  resource_path      = each.value.resource_path
  failure_threshold  = each.value.failure_threshold
  request_interval   = each.value.request_interval

  tags = merge(var.tags, {
    Name = "${var.project_name}-healthcheck-${each.value.fqdn}"
  })
}

# ----------------------------------------------
# DNSSEC (optional)
# ----------------------------------------------
resource "aws_route53_key_signing_key" "this" {
  count                      = var.enable_dnssec && !var.private_zone ? 1 : 0
  hosted_zone_id             = aws_route53_zone.this.id
  key_management_service_arn = var.dnssec_kms_key_arn
  name                       = "${var.project_name}-dnssec-ksk"
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  count          = var.enable_dnssec && !var.private_zone ? 1 : 0
  hosted_zone_id = aws_route53_zone.this.id

  depends_on = [aws_route53_key_signing_key.this]
}
