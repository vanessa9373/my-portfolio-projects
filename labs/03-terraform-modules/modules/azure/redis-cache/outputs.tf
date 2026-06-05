# ============================================================
# Azure Redis Cache Module — Outputs
# Author: Jenella Awo
# ============================================================

output "redis_id" {
  description = "ID of the Redis cache"
  value       = azurerm_redis_cache.this.id
}

output "hostname" {
  description = "Hostname of the Redis cache"
  value       = azurerm_redis_cache.this.hostname
}

output "ssl_port" {
  description = "SSL port of the Redis cache"
  value       = azurerm_redis_cache.this.ssl_port
}

output "primary_access_key" {
  description = "Primary access key for the Redis cache"
  value       = azurerm_redis_cache.this.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "Primary connection string for the Redis cache"
  value       = azurerm_redis_cache.this.primary_connection_string
  sensitive   = true
}
