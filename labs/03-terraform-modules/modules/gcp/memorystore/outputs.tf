# ============================================================
# Memorystore Module — Outputs
# Author: Jenella Awo
# ============================================================

output "instance_id" {
  description = "ID of the Redis instance"
  value       = google_redis_instance.this.id
}

output "host" {
  description = "Hostname/IP of the Redis instance"
  value       = google_redis_instance.this.host
}

output "port" {
  description = "Port of the Redis instance"
  value       = google_redis_instance.this.port
}

output "current_location_id" {
  description = "Current location of the Redis instance"
  value       = google_redis_instance.this.current_location_id
}

output "read_endpoint" {
  description = "Read endpoint IP (STANDARD_HA only)"
  value       = google_redis_instance.this.read_endpoint
}

output "auth_string" {
  description = "AUTH string for the Redis instance"
  value       = google_redis_instance.this.auth_string
  sensitive   = true
}
