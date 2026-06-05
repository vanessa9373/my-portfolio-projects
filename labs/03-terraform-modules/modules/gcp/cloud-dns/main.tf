# ============================================================
# Cloud DNS Module — Public & Private Managed Zones
# Author: Jenella Awo
# ============================================================

# --- Managed Zone ---
resource "google_dns_managed_zone" "this" {
  project     = var.project_id
  name        = "${var.project_name}-${replace(var.domain_name, ".", "-")}"
  dns_name    = "${var.domain_name}."
  description = "Managed zone for ${var.domain_name}"
  visibility  = var.private_zone ? "private" : "public"

  dynamic "private_visibility_config" {
    for_each = var.private_zone && var.network != null ? [1] : []
    content {
      networks {
        network_url = var.network
      }
    }
  }

  dynamic "dnssec_config" {
    for_each = var.enable_dnssec && !var.private_zone ? [1] : []
    content {
      state = "on"
      default_key_specs {
        algorithm  = "rsasha256"
        key_length = 2048
        key_type   = "keySigning"
      }
      default_key_specs {
        algorithm  = "rsasha256"
        key_length = 1024
        key_type   = "zoneSigning"
      }
    }
  }

  labels = var.tags
}

# --- DNS Records ---
resource "google_dns_record_set" "this" {
  for_each     = { for r in var.records : "${r.name}-${r.type}" => r }
  project      = var.project_id
  managed_zone = google_dns_managed_zone.this.name
  name         = each.value.name == "" ? "${var.domain_name}." : "${each.value.name}.${var.domain_name}."
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.rrdatas
}
