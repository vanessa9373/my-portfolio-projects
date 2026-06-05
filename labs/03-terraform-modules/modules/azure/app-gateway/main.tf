# ============================================================
# App Gateway Module — Azure Application Gateway v2 with WAF,
#   HTTP/HTTPS listeners, backend pools, SSL, URL routing,
#   redirect configurations, and autoscaling
# Author: Jenella Awo
# ============================================================

locals {
  gateway_ip_config_name  = "${var.project_name}-appgw-ip-config"
  frontend_ip_config_name = "${var.project_name}-appgw-feip"
  frontend_port_http      = "${var.project_name}-appgw-feport-http"
  frontend_port_https     = "${var.project_name}-appgw-feport-https"
}

# ------------------------------------
# Public IP
# ------------------------------------
resource "azurerm_public_ip" "appgw" {
  name                = "${var.project_name}-appgw-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = merge(var.tags, { Name = "${var.project_name}-appgw-pip" })
}

# ------------------------------------
# WAF Policy (optional)
# ------------------------------------
resource "azurerm_web_application_firewall_policy" "this" {
  count = var.enable_waf ? 1 : 0

  name                = "${var.project_name}-waf-policy"
  location            = var.location
  resource_group_name = var.resource_group_name

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-waf-policy" })
}

# ------------------------------------
# Application Gateway
# ------------------------------------
resource "azurerm_application_gateway" "this" {
  name                = "${var.project_name}-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name
  firewall_policy_id  = var.enable_waf ? azurerm_web_application_firewall_policy.this[0].id : null

  sku {
    name = var.enable_waf ? "WAF_v2" : "Standard_v2"
    tier = var.enable_waf ? "WAF_v2" : "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_config_name
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_config_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.frontend_port_http
    port = 80
  }

  frontend_port {
    name = local.frontend_port_https
    port = 443
  }

  # --- Backend Address Pools ---
  dynamic "backend_address_pool" {
    for_each = var.backend_pools
    content {
      name         = backend_pool.value.name
      fqdns        = lookup(backend_pool.value, "fqdns", null)
      ip_addresses = lookup(backend_pool.value, "ip_addresses", null)
    }
  }

  # --- Backend HTTP Settings ---
  dynamic "backend_http_settings" {
    for_each = var.backend_pools
    content {
      name                  = "${backend_http_settings.value.name}-settings"
      cookie_based_affinity = lookup(backend_http_settings.value, "cookie_affinity", "Disabled")
      port                  = lookup(backend_http_settings.value, "port", 80)
      protocol              = lookup(backend_http_settings.value, "protocol", "Http")
      request_timeout       = lookup(backend_http_settings.value, "request_timeout", 30)
      probe_name            = lookup(backend_http_settings.value, "probe_name", null)
    }
  }

  # --- Health Probes ---
  dynamic "probe" {
    for_each = [for pool in var.backend_pools : pool if lookup(pool, "probe_path", null) != null]
    content {
      name                = "${probe.value.name}-probe"
      protocol            = lookup(probe.value, "protocol", "Http")
      path                = probe.value.probe_path
      host                = lookup(probe.value, "probe_host", null)
      interval            = lookup(probe.value, "probe_interval", 30)
      timeout             = lookup(probe.value, "probe_timeout", 30)
      unhealthy_threshold = lookup(probe.value, "probe_unhealthy_threshold", 3)
    }
  }

  # --- HTTP Listeners ---
  dynamic "http_listener" {
    for_each = var.http_listeners
    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = local.frontend_ip_config_name
      frontend_port_name             = http_listener.value.protocol == "Https" ? local.frontend_port_https : local.frontend_port_http
      protocol                       = http_listener.value.protocol
      ssl_certificate_name           = lookup(http_listener.value, "ssl_certificate_name", null)
      host_name                      = lookup(http_listener.value, "host_name", null)
      host_names                     = lookup(http_listener.value, "host_names", null)
    }
  }

  # --- SSL Certificates ---
  dynamic "ssl_certificate" {
    for_each = var.ssl_certificates
    content {
      name                = ssl_certificate.value.name
      key_vault_secret_id = lookup(ssl_certificate.value, "key_vault_secret_id", null)
      data                = lookup(ssl_certificate.value, "pfx_data", null)
      password            = lookup(ssl_certificate.value, "pfx_password", null)
    }
  }

  # --- Routing Rules ---
  dynamic "request_routing_rule" {
    for_each = var.routing_rules
    content {
      name                       = request_routing_rule.value.name
      priority                   = request_routing_rule.value.priority
      rule_type                  = lookup(request_routing_rule.value, "rule_type", "Basic")
      http_listener_name         = request_routing_rule.value.http_listener_name
      backend_address_pool_name  = lookup(request_routing_rule.value, "backend_address_pool_name", null)
      backend_http_settings_name = lookup(request_routing_rule.value, "backend_http_settings_name", null)
      url_path_map_name          = lookup(request_routing_rule.value, "url_path_map_name", null)
      redirect_configuration_name = lookup(request_routing_rule.value, "redirect_configuration_name", null)
    }
  }

  # --- URL Path Maps ---
  dynamic "url_path_map" {
    for_each = var.url_path_maps
    content {
      name                               = url_path_map.value.name
      default_backend_address_pool_name  = url_path_map.value.default_backend_address_pool_name
      default_backend_http_settings_name = url_path_map.value.default_backend_http_settings_name

      dynamic "path_rule" {
        for_each = url_path_map.value.path_rules
        content {
          name                       = path_rule.value.name
          paths                      = path_rule.value.paths
          backend_address_pool_name  = path_rule.value.backend_address_pool_name
          backend_http_settings_name = path_rule.value.backend_http_settings_name
        }
      }
    }
  }

  # --- Redirect Configurations ---
  dynamic "redirect_configuration" {
    for_each = var.redirect_configurations
    content {
      name                 = redirect_configuration.value.name
      redirect_type        = redirect_configuration.value.redirect_type
      target_listener_name = lookup(redirect_configuration.value, "target_listener_name", null)
      target_url           = lookup(redirect_configuration.value, "target_url", null)
      include_path         = lookup(redirect_configuration.value, "include_path", true)
      include_query_string = lookup(redirect_configuration.value, "include_query_string", true)
    }
  }

  identity {
    type         = length(var.ssl_certificates) > 0 ? "UserAssigned" : null
    identity_ids = length(var.ssl_certificates) > 0 && var.identity_ids != null ? var.identity_ids : null
  }

  tags = merge(var.tags, { Name = "${var.project_name}-appgw" })

  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      http_listener,
      request_routing_rule,
      probe,
      frontend_port,
    ]
  }
}
