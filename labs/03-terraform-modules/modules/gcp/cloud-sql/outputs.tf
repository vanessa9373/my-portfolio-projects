# ============================================================
# Cloud SQL Module — Outputs
# Author: Jenella Awo
# ============================================================

output "instance_name" {
  description = "The name of the Cloud SQL primary instance"
  value       = google_sql_database_instance.primary.name
}

output "instance_connection_name" {
  description = "Connection name for Cloud SQL Proxy (project:region:instance)"
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.primary.private_ip_address
}

output "public_ip" {
  description = "Public IP address of the Cloud SQL instance (null if private only)"
  value       = google_sql_database_instance.primary.public_ip_address
}

output "database_name" {
  description = "Name of the default database created on the instance"
  value       = google_sql_database.default.name
}

output "server_ca_cert" {
  description = "SSL CA certificate for the Cloud SQL instance"
  value       = google_sql_database_instance.primary.server_ca_cert[0].cert
  sensitive   = true
}
