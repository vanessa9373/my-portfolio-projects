# ============================================================
# Key Vault Module — Outputs
# Author: Jenella Awo
# ============================================================

output "vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "vault_name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.this.name
}
