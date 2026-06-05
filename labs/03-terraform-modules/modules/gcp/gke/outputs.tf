# ============================================================
# GKE Module — Outputs
# Author: Jenella Awo
# ============================================================

output "cluster_id" {
  description = "The unique identifier of the GKE cluster"
  value       = google_container_cluster.cluster.id
}

output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "The IP address of the Kubernetes master endpoint"
  value       = google_container_cluster.cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate authority of the cluster"
  value       = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "location" {
  description = "The region/location of the GKE cluster"
  value       = google_container_cluster.cluster.location
}
