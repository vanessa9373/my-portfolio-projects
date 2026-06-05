# ============================================================
# Load Balancer Module — Global HTTP(S) LB with Cloud CDN and Cloud Armor
# Author: Jenella Awo
# ============================================================

# ---------- Global IP Address ----------

resource "google_compute_global_address" "lb_ip" {
  project = var.project_id
  name    = "${var.project_name}-lb-ip"
}

# ---------- Health Checks ----------

resource "google_compute_health_check" "health_checks" {
  for_each = { for b in var.backends : b.name => b }

  project = var.project_id
  name    = "${var.project_name}-hc-${each.value.name}"

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = each.value.port
    request_path = each.value.health_check_path
  }
}

# ---------- Backend Services ----------

resource "google_compute_backend_service" "backends" {
  for_each = { for b in var.backends : b.name => b }

  project     = var.project_id
  name        = "${var.project_name}-bs-${each.value.name}"
  protocol    = each.value.protocol
  port_name   = "http"
  timeout_sec = 30

  health_checks = [google_compute_health_check.health_checks[each.key].id]

  backend {
    group           = each.value.group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }

  # Cloud CDN
  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode                   = lookup(var.cdn_config, "cache_mode", "CACHE_ALL_STATIC")
      default_ttl                  = lookup(var.cdn_config, "default_ttl", 3600)
      max_ttl                      = lookup(var.cdn_config, "max_ttl", 86400)
      client_ttl                   = lookup(var.cdn_config, "client_ttl", 3600)
      serve_while_stale            = lookup(var.cdn_config, "serve_while_stale", 86400)
      signed_url_cache_max_age_sec = lookup(var.cdn_config, "signed_url_cache_max_age", 0)
    }
  }

  enable_cdn = var.enable_cdn

  # Cloud Armor security policy
  security_policy = var.security_policy

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ---------- URL Map ----------

resource "google_compute_url_map" "url_map" {
  project = var.project_id
  name    = "${var.project_name}-url-map"

  default_service = google_compute_backend_service.backends[var.backends[0].name].id

  dynamic "host_rule" {
    for_each = length(var.backends) > 1 ? [1] : []
    content {
      hosts        = [var.domain_name]
      path_matcher = "default-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = length(var.backends) > 1 ? [1] : []
    content {
      name            = "default-matcher"
      default_service = google_compute_backend_service.backends[var.backends[0].name].id

      dynamic "path_rule" {
        for_each = { for b in slice(var.backends, 1, length(var.backends)) : b.name => b if lookup(b, "path", null) != null }
        content {
          paths   = [lookup(path_rule.value, "path", "/*")]
          service = google_compute_backend_service.backends[path_rule.key].id
        }
      }
    }
  }
}

# ---------- SSL Certificate (managed) ----------

resource "google_compute_managed_ssl_certificate" "cert" {
  count   = length(var.ssl_certificates) == 0 ? 1 : 0
  project = var.project_id
  name    = "${var.project_name}-ssl-cert"

  managed {
    domains = [var.domain_name]
  }
}

# ---------- HTTPS Proxy ----------

resource "google_compute_target_https_proxy" "https_proxy" {
  project = var.project_id
  name    = "${var.project_name}-https-proxy"
  url_map = google_compute_url_map.url_map.id

  ssl_certificates = length(var.ssl_certificates) > 0 ? var.ssl_certificates : [google_compute_managed_ssl_certificate.cert[0].id]
}

# ---------- Global Forwarding Rule (HTTPS) ----------

resource "google_compute_global_forwarding_rule" "https" {
  project    = var.project_id
  name       = "${var.project_name}-https-rule"
  target     = google_compute_target_https_proxy.https_proxy.id
  port_range = "443"
  ip_address = google_compute_global_address.lb_ip.address

  labels = var.tags
}

# ---------- HTTP to HTTPS Redirect ----------

resource "google_compute_url_map" "http_redirect" {
  project = var.project_id
  name    = "${var.project_name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "http_proxy" {
  project = var.project_id
  name    = "${var.project_name}-http-proxy"
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "http" {
  project    = var.project_id
  name       = "${var.project_name}-http-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.lb_ip.address

  labels = var.tags
}
