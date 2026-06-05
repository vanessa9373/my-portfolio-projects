# ============================================================
# VPC Module — GCP VPC Network with subnets, Cloud NAT, and firewall
# Author: Jenella Awo
# ============================================================

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  description             = "VPC network for ${var.project_name}"
}

# ---------- Subnets ----------

resource "google_compute_subnetwork" "subnets" {
  for_each = { for s in var.subnets : s.name => s }

  project                  = var.project_id
  name                     = "${var.project_name}-${each.value.name}"
  ip_cidr_range            = each.value.cidr
  region                   = each.value.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  dynamic "secondary_ip_range" {
    for_each = lookup(each.value, "secondary_ranges", [])
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# ---------- Shared VPC (optional) ----------

resource "google_compute_shared_vpc_host_project" "host" {
  count   = var.enable_shared_vpc ? 1 : 0
  project = var.project_id
}

# ---------- Cloud Router ----------

resource "google_compute_router" "router" {
  count   = var.enable_nat ? 1 : 0
  project = var.project_id
  name    = "${var.project_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# ---------- Cloud NAT ----------

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_nat ? 1 : 0
  project                            = var.project_id
  name                               = "${var.project_name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------- Firewall Rules ----------

resource "google_compute_firewall" "rules" {
  for_each = { for r in var.firewall_rules : r.name => r }

  project     = var.project_id
  name        = "${var.project_name}-${each.value.name}"
  network     = google_compute_network.vpc.id
  description = lookup(each.value, "description", "Managed by Terraform")
  direction   = lookup(each.value, "direction", "INGRESS")
  priority    = lookup(each.value, "priority", 1000)

  source_ranges      = lookup(each.value, "direction", "INGRESS") == "INGRESS" ? lookup(each.value, "source_ranges", []) : null
  destination_ranges = lookup(each.value, "direction", "INGRESS") == "EGRESS" ? lookup(each.value, "destination_ranges", []) : null
  source_tags        = lookup(each.value, "source_tags", null)
  target_tags        = lookup(each.value, "target_tags", null)

  dynamic "allow" {
    for_each = lookup(each.value, "allow", [])
    content {
      protocol = allow.value.protocol
      ports    = lookup(allow.value, "ports", null)
    }
  }

  dynamic "deny" {
    for_each = lookup(each.value, "deny", [])
    content {
      protocol = deny.value.protocol
      ports    = lookup(deny.value, "ports", null)
    }
  }
}
