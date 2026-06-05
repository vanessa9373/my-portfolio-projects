# ============================================================
# Artifact Registry Module — Outputs
# Author: Jenella Awo
# ============================================================

output "repository_id" {
  description = "ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.repo.id
}

output "repository_name" {
  description = "Name of the repository"
  value       = google_artifact_registry_repository.repo.name
}

output "repository_url" {
  description = "URL for accessing the repository (e.g., for docker push)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.name}"
}
