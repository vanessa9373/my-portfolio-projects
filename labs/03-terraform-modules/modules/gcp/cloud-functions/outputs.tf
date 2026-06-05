# ============================================================
# Cloud Functions Module — Outputs
# Author: Jenella Awo
# ============================================================

output "function_id" {
  description = "The unique identifier of the Cloud Function"
  value       = google_cloudfunctions2_function.function.id
}

output "function_name" {
  description = "The name of the Cloud Function"
  value       = google_cloudfunctions2_function.function.name
}

output "function_url" {
  description = "The URL of the Cloud Function (HTTPS endpoint for HTTP triggers)"
  value       = google_cloudfunctions2_function.function.service_config[0].uri
}

output "trigger_url" {
  description = "The trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.function.url
}
