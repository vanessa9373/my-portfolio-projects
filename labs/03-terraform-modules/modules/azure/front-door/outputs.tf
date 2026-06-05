# ============================================================
# Azure Front Door Module — Outputs
# Author: Jenella Awo
# ============================================================

output "front_door_id" {
  description = "ID of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.this.id
}

output "endpoint_hostname" {
  description = "Hostname of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "profile_name" {
  description = "Name of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.this.name
}

output "waf_policy_id" {
  description = "ID of the WAF policy"
  value       = var.enable_waf ? azurerm_cdn_frontdoor_firewall_policy.this[0].id : null
}
