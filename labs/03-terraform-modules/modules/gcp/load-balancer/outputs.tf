# ============================================================
# Load Balancer Module — Outputs
# Author: Jenella Awo
# ============================================================

output "lb_ip_address" {
  description = "The global IP address of the load balancer"
  value       = google_compute_global_address.lb_ip.address
}

output "lb_ip_address_name" {
  description = "The name of the global IP address resource"
  value       = google_compute_global_address.lb_ip.name
}

output "url_map_id" {
  description = "The unique identifier of the URL map"
  value       = google_compute_url_map.url_map.id
}

output "backend_service_ids" {
  description = "Map of backend service names to their unique identifiers"
  value       = { for k, v in google_compute_backend_service.backends : k => v.id }
}
