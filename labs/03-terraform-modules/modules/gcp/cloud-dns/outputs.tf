# ============================================================
# Cloud DNS Module — Outputs
# Author: Jenella Awo
# ============================================================

output "zone_id" {
  description = "ID of the DNS managed zone"
  value       = google_dns_managed_zone.this.id
}

output "zone_name" {
  description = "Name of the DNS managed zone"
  value       = google_dns_managed_zone.this.name
}

output "name_servers" {
  description = "Name servers for the DNS zone"
  value       = google_dns_managed_zone.this.name_servers
}

output "dns_name" {
  description = "DNS name of the managed zone"
  value       = google_dns_managed_zone.this.dns_name
}
