# ============================================================
# Cloud Storage Module — Outputs
# Author: Jenella Awo
# ============================================================

output "bucket_id" {
  description = "The unique identifier of the GCS bucket"
  value       = google_storage_bucket.bucket.id
}

output "bucket_name" {
  description = "The name of the GCS bucket"
  value       = google_storage_bucket.bucket.name
}

output "bucket_url" {
  description = "The gs:// URL of the bucket"
  value       = google_storage_bucket.bucket.url
}

output "bucket_self_link" {
  description = "The URI of the bucket in GCP"
  value       = google_storage_bucket.bucket.self_link
}
