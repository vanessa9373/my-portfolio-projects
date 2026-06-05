# ============================================================
# VPC Module — Outputs
# Author: Jenella Awo
# ============================================================

output "network_id" {
  description = "The unique identifier of the VPC network"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "The URI of the VPC network in GCP"
  value       = google_compute_network.vpc.self_link
}

output "subnet_ids" {
  description = "Map of subnet names to their unique identifiers"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.id }
}

output "subnet_self_links" {
  description = "Map of subnet names to their self-link URIs"
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.self_link }
}

output "router_id" {
  description = "The unique identifier of the Cloud Router (null if NAT disabled)"
  value       = var.enable_nat ? google_compute_router.router[0].id : null
}

output "nat_id" {
  description = "The unique identifier of the Cloud NAT gateway (null if NAT disabled)"
  value       = var.enable_nat ? google_compute_router_nat.nat[0].id : null
}
