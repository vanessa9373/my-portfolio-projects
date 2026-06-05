# ============================================================
# Cloud Run Module — Outputs
# Author: Jenella Awo
# ============================================================

output "service_id" {
  description = "ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.this.id
}

output "service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.this.uri
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.this.name
}

output "latest_revision" {
  description = "Latest ready revision name"
  value       = google_cloud_run_v2_service.this.latest_ready_revision
}
