# ============================================================
# Cloud Storage Module — GCS bucket with lifecycle, versioning, and encryption
# Author: Jenella Awo
# ============================================================

resource "google_storage_bucket" "bucket" {
  project                     = var.project_id
  name                        = "${var.project_name}-${var.bucket_name}"
  location                    = var.location
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.uniform_access
  force_destroy               = false

  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle rules
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action_type
        storage_class = lookup(lifecycle_rule.value, "storage_class", null)
      }
      condition {
        age                   = lookup(lifecycle_rule.value, "age_days", null)
        created_before        = lookup(lifecycle_rule.value, "created_before", null)
        with_state            = lookup(lifecycle_rule.value, "with_state", null)
        num_newer_versions    = lookup(lifecycle_rule.value, "num_newer_versions", null)
        matches_storage_class = lookup(lifecycle_rule.value, "matches_storage_class", null)
      }
    }
  }

  # CMEK encryption
  dynamic "encryption" {
    for_each = var.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = var.kms_key_name
    }
  }

  # CORS configuration
  dynamic "cors" {
    for_each = var.cors_rules
    content {
      origin          = cors.value.origins
      method          = cors.value.methods
      response_header = lookup(cors.value, "response_headers", [])
      max_age_seconds = lookup(cors.value, "max_age_seconds", 3600)
    }
  }

  # Retention policy
  dynamic "retention_policy" {
    for_each = var.retention_period_days != null ? [1] : []
    content {
      retention_period = var.retention_period_days * 86400
      is_locked        = false
    }
  }

  # Access logging
  dynamic "logging" {
    for_each = var.logging_bucket != null ? [1] : []
    content {
      log_bucket        = var.logging_bucket
      log_object_prefix = "${var.project_name}-${var.bucket_name}/"
    }
  }

  # Static website hosting
  dynamic "website" {
    for_each = var.enable_website ? [1] : []
    content {
      main_page_suffix = lookup(var.website_config, "main_page_suffix", "index.html")
      not_found_page   = lookup(var.website_config, "not_found_page", "404.html")
    }
  }

  labels = var.tags
}
