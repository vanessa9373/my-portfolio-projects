# ============================================================
# IAM Module — Service accounts, role bindings, and Workload Identity
# Author: Jenella Awo
# ============================================================

# ---------- Service Account ----------

resource "google_service_account" "sa" {
  project      = var.project_id
  account_id   = "${var.project_name}-${var.service_account_name}"
  display_name = var.display_name
  description  = "Service account for ${var.project_name} managed by Terraform"
}

# ---------- IAM Role Bindings (project-level) ----------

resource "google_project_iam_member" "roles" {
  for_each = toset(var.roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.sa.email}"
}

# ---------- Workload Identity Binding ----------

resource "google_service_account_iam_member" "workload_identity" {
  count = var.workload_identity_namespace != null ? 1 : 0

  service_account_id = google_service_account.sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_identity_namespace}[${var.workload_identity_sa}]"
}

# ---------- Custom Role (optional) ----------

resource "google_project_iam_custom_role" "custom" {
  count = var.create_custom_role ? 1 : 0

  project     = var.project_id
  role_id     = replace("${var.project_name}_${var.service_account_name}_custom", "-", "_")
  title       = "${var.project_name} ${var.service_account_name} Custom Role"
  description = "Custom role for ${var.project_name} managed by Terraform"
  permissions = var.custom_role_permissions
  stage       = "GA"
}

resource "google_project_iam_member" "custom_role_binding" {
  count = var.create_custom_role ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.custom[0].id
  member  = "serviceAccount:${google_service_account.sa.email}"
}
