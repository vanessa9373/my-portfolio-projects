# ============================================================
# Security Group Module — Reusable Security Group with
# Configurable Ingress/Egress Rules (CIDR and SG-based)
# Author: Jenella Awo
# ============================================================

locals {
  sg_name = "${var.project_name}-${var.sg_name}"
}

# ----------------------------------------------
# Security Group
# ----------------------------------------------
resource "aws_security_group" "this" {
  name        = local.sg_name
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = local.sg_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ----------------------------------------------
# Ingress Rules (CIDR-based)
# ----------------------------------------------
resource "aws_security_group_rule" "ingress_cidr" {
  for_each = {
    for idx, rule in var.ingress_rules : idx => rule
    if rule.cidr_blocks != null && length(rule.cidr_blocks) > 0
  }

  type              = "ingress"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  description       = each.value.description
  security_group_id = aws_security_group.this.id
}

# ----------------------------------------------
# Ingress Rules (Security Group-based)
# ----------------------------------------------
resource "aws_security_group_rule" "ingress_sg" {
  for_each = {
    for idx, rule in var.ingress_rules : idx => rule
    if rule.source_security_group_id != null
  }

  type                     = "ingress"
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  source_security_group_id = each.value.source_security_group_id
  description              = each.value.description
  security_group_id        = aws_security_group.this.id
}

# ----------------------------------------------
# Egress Rules
# ----------------------------------------------
resource "aws_security_group_rule" "egress" {
  for_each = { for idx, rule in var.egress_rules : idx => rule }

  type              = "egress"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  description       = each.value.description
  security_group_id = aws_security_group.this.id
}
