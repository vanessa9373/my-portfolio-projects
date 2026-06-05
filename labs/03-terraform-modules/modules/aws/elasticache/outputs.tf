# ============================================================
# ElastiCache Module — Outputs
# Author: Jenella Awo
# ============================================================

output "primary_endpoint" {
  description = "Primary endpoint address for Redis replication group"
  value       = var.engine == "redis" ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : null
}

output "reader_endpoint" {
  description = "Reader endpoint address for Redis replication group"
  value       = var.engine == "redis" ? aws_elasticache_replication_group.redis[0].reader_endpoint_address : null
}

output "configuration_endpoint" {
  description = "Configuration endpoint for Memcached or Redis cluster mode"
  value = var.engine == "redis" ? (
    aws_elasticache_replication_group.redis[0].configuration_endpoint_address
  ) : aws_elasticache_cluster.memcached[0].configuration_endpoint
}

output "port" {
  description = "Port number for the cache cluster"
  value       = var.engine == "redis" ? 6379 : 11211
}
