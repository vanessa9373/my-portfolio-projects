# ============================================================
# ACR Module — Outputs
# Author: Jenella Awo
# ============================================================

output "acr_id" {
  description = "The ID of the container registry"
  value       = azurerm_container_registry.this.id
}

output "acr_name" {
  description = "The name of the container registry"
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "The login server URL of the container registry"
  value       = azurerm_container_registry.this.login_server
}

output "admin_username" {
  description = "The admin username for the container registry (if admin is enabled)"
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_username : null
}

output "admin_password" {
  description = "The admin password for the container registry (if admin is enabled)"
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_password : null
  sensitive   = true
}
