# ============================================================
# Route53 Module — Outputs
# Author: Jenella Awo
# ============================================================

output "zone_id" {
  description = "ID of the Route53 hosted zone"
  value       = aws_route53_zone.this.zone_id
}

output "zone_name" {
  description = "Name of the Route53 hosted zone"
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Name servers for the hosted zone"
  value       = aws_route53_zone.this.name_servers
}
