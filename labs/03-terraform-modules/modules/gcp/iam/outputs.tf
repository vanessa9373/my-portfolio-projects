# ============================================================
# IAM Module — Outputs
# Author: Jenella Awo
# ============================================================

output "service_account_email" {
  description = "Email address of the created service account"
  value       = google_service_account.sa.email
}

output "service_account_id" {
  description = "Unique identifier of the service account"
  value       = google_service_account.sa.id
}

output "service_account_name" {
  description = "Fully-qualified name of the service account"
  value       = google_service_account.sa.name
}

output "custom_role_id" {
  description = "ID of the custom role (null if not created)"
  value       = var.create_custom_role ? google_project_iam_custom_role.custom[0].id : null
}
