# ============================================================
# Azure DNS Module — Outputs
# Author: Jenella Awo
# ============================================================

output "zone_id" {
  description = "ID of the DNS zone"
  value       = var.private_zone ? azurerm_private_dns_zone.private[0].id : azurerm_dns_zone.public[0].id
}

output "zone_name" {
  description = "Name of the DNS zone"
  value       = var.domain_name
}

output "name_servers" {
  description = "Name servers for the public DNS zone"
  value       = var.private_zone ? [] : azurerm_dns_zone.public[0].name_servers
}
