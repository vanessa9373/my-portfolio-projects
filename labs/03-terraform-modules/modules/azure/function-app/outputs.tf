# ============================================================
# Azure Function App Module — Outputs
# Author: Jenella Awo
# ============================================================

output "function_app_id" {
  description = "ID of the Function App"
  value       = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.this.name
}

output "default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.this.default_hostname
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity"
  value       = azurerm_linux_function_app.this.identity[0].principal_id
}

output "app_insights_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_app_insights ? azurerm_application_insights.this[0].instrumentation_key : null
}
