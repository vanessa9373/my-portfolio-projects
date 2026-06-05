# ============================================================
# Cloud SQL Module — Managed PostgreSQL/MySQL with HA and backups
# Author: Jenella Awo
# ============================================================

resource "random_id" "db_suffix" {
  byte_length = 4
}

# ---------- Primary Instance ----------

resource "google_sql_database_instance" "primary" {
  project             = var.project_id
  name                = "${var.project_name}-db-${random_id.db_suffix.hex}"
  database_version    = var.database_version
  region              = var.region
  deletion_protection = true

  encryption_key_name = var.kms_key_name

  settings {
    tier              = var.tier
    disk_size         = var.disk_size
    disk_type         = var.disk_type
    disk_autoresize   = true
    availability_type = var.availability_type

    ip_configuration {
      ipv4_enabled    = var.enable_private_ip ? false : true
      private_network = var.enable_private_ip ? var.network : null
      require_ssl     = true

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.cidr
        }
      }
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      point_in_time_recovery_enabled = var.pitr_enabled
      start_time                     = "02:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = var.enable_insights
      query_plans_per_minute  = var.enable_insights ? 5 : 0
      query_string_length     = var.enable_insights ? 1024 : 0
      record_application_tags = var.enable_insights
      record_client_address   = var.enable_insights
    }

    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    user_labels = var.tags
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ---------- Database ----------

resource "google_sql_database" "default" {
  project  = var.project_id
  name     = "${var.project_name}-database"
  instance = google_sql_database_instance.primary.name
}

# ---------- Read Replicas ----------

resource "google_sql_database_instance" "read_replica" {
  count                = var.read_replica_count
  project              = var.project_id
  name                 = "${var.project_name}-db-replica-${count.index}-${random_id.db_suffix.hex}"
  master_instance_name = google_sql_database_instance.primary.name
  database_version     = var.database_version
  region               = var.region

  encryption_key_name = var.kms_key_name

  replica_configuration {
    failover_target = false
  }

  settings {
    tier            = var.tier
    disk_size       = var.disk_size
    disk_type       = var.disk_type
    disk_autoresize = true

    ip_configuration {
      ipv4_enabled    = var.enable_private_ip ? false : true
      private_network = var.enable_private_ip ? var.network : null
      require_ssl     = true
    }

    user_labels = var.tags
  }
}
