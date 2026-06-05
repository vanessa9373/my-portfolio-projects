# ============================================================
# App Gateway Module — Outputs
# Author: Jenella Awo
# ============================================================

output "app_gateway_id" {
  description = "The ID of the Application Gateway"
  value       = azurerm_application_gateway.this.id
}

output "public_ip_address" {
  description = "The public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "backend_address_pools" {
  description = "Map of backend address pool names to their IDs"
  value       = { for pool in azurerm_application_gateway.this.backend_address_pool : pool.name => pool.id }
}
