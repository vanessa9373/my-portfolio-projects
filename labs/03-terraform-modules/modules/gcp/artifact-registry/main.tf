# ============================================================
# Artifact Registry Module — Container and package repository
# Author: Jenella Awo
# ============================================================

# ---------- Repository ----------

resource "google_artifact_registry_repository" "repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.project_name}-${var.repository_name}"
  format        = var.format
  description   = var.description

  kms_key_name = var.kms_key_name

  dynamic "cleanup_policies" {
    for_each = var.cleanup_policies
    content {
      id     = cleanup_policies.value.id
      action = lookup(cleanup_policies.value, "action", "DELETE")

      dynamic "condition" {
        for_each = lookup(cleanup_policies.value, "condition", null) != null ? [cleanup_policies.value.condition] : []
        content {
          tag_state             = lookup(condition.value, "tag_state", null)
          tag_prefixes          = lookup(condition.value, "tag_prefixes", null)
          older_than            = lookup(condition.value, "older_than", null)
          newer_than            = lookup(condition.value, "newer_than", null)
          package_name_prefixes = lookup(condition.value, "package_name_prefixes", null)
          version_name_prefixes = lookup(condition.value, "version_name_prefixes", null)
        }
      }

      dynamic "most_recent_versions" {
        for_each = lookup(cleanup_policies.value, "most_recent_versions", null) != null ? [cleanup_policies.value.most_recent_versions] : []
        content {
          keep_count            = lookup(most_recent_versions.value, "keep_count", null)
          package_name_prefixes = lookup(most_recent_versions.value, "package_name_prefixes", null)
        }
      }
    }
  }

  labels = var.tags
}

# ---------- IAM Bindings ----------

resource "google_artifact_registry_repository_iam_member" "members" {
  for_each = { for m in var.iam_members : "${m.role}-${m.member}" => m }

  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.repo.name
  role       = each.value.role
  member     = each.value.member
}
