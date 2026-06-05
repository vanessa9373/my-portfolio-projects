# ============================================================
# Memorystore Module — Managed Redis for GCP
# Author: Jenella Awo
# ============================================================

resource "google_redis_instance" "this" {
  project            = var.project_id
  name               = "${var.project_name}-${var.instance_name}"
  region             = var.region
  tier               = var.tier
  memory_size_gb     = var.memory_size_gb
  redis_version      = var.redis_version
  display_name       = "${var.project_name} Redis"
  authorized_network = var.authorized_network
  reserved_ip_range  = var.reserved_ip_range
  auth_enabled       = var.auth_enabled
  transit_encryption_mode = var.transit_encryption ? "SERVER_AUTHENTICATION" : "DISABLED"

  redis_configs = var.redis_configs

  dynamic "maintenance_policy" {
    for_each = var.maintenance_window != null ? [var.maintenance_window] : []
    content {
      weekly_maintenance_window {
        day = maintenance_policy.value.day
        start_time {
          hours   = maintenance_policy.value.hour
          minutes = 0
          seconds = 0
          nanos   = 0
        }
      }
    }
  }

  labels = var.tags

  lifecycle {
    prevent_destroy = false
  }
}
