# ============================================================
# Cloud Functions Module — 2nd gen Cloud Functions with event triggers
# Author: Jenella Awo
# ============================================================

# ---------- Source archive ----------

data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/tmp/${var.function_name}-source.zip"
}

resource "google_storage_bucket" "source_bucket" {
  project                     = var.project_id
  name                        = "${var.project_name}-${var.function_name}-source"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = var.tags
}

resource "google_storage_bucket_object" "source_archive" {
  name   = "source-${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.source_bucket.name
  source = data.archive_file.source.output_path
}

# ---------- Cloud Function (2nd gen) ----------

resource "google_cloudfunctions2_function" "function" {
  project  = var.project_id
  name     = "${var.project_name}-${var.function_name}"
  location = var.region

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.source_archive.name
      }
    }
  }

  service_config {
    max_instance_count    = var.max_instances
    min_instance_count    = var.min_instances
    available_memory      = var.memory
    timeout_seconds       = var.timeout
    service_account_email = var.service_account_email

    environment_variables = var.environment_variables

    dynamic "secret_environment_variables" {
      for_each = lookup(var.trigger_config, "secrets", {})
      content {
        key        = secret_environment_variables.key
        project_id = var.project_id
        secret     = secret_environment_variables.value.secret_name
        version    = lookup(secret_environment_variables.value, "version", "latest")
      }
    }

    vpc_connector                 = var.vpc_connector
    vpc_connector_egress_settings = var.vpc_connector != null ? "PRIVATE_RANGES_ONLY" : null
  }

  # HTTP trigger
  dynamic "event_trigger" {
    for_each = var.trigger_type != "http" ? [1] : []
    content {
      trigger_region = var.region
      event_type     = var.trigger_type == "pubsub" ? "google.cloud.pubsub.topic.v1.messagePublished" : "google.cloud.storage.object.v1.finalized"
      pubsub_topic   = var.trigger_type == "pubsub" ? lookup(var.trigger_config, "topic", null) : null
      retry_policy   = lookup(var.trigger_config, "retry_policy", "RETRY_POLICY_DO_NOT_RETRY")

      dynamic "event_filters" {
        for_each = var.trigger_type == "storage" ? [1] : []
        content {
          attribute = "bucket"
          value     = lookup(var.trigger_config, "bucket", "")
        }
      }
    }
  }

  labels = var.tags
}

# ---------- IAM: Allow unauthenticated invocations for HTTP ----------

resource "google_cloud_run_service_iam_member" "invoker" {
  count = var.trigger_type == "http" && lookup(var.trigger_config, "allow_unauthenticated", false) ? 1 : 0

  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
