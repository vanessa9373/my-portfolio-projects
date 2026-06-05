# ============================================================
# Azure Front Door Module — Global Load Balancing & CDN
# Author: Jenella Awo
# ============================================================

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.project_name}-fd"
  resource_group_name = var.resource_group_name
  sku_name            = var.enable_waf ? "Premium_AzureFrontDoor" : "Standard_AzureFrontDoor"
  tags                = merge(var.tags, { Name = "${var.project_name}-fd" })
}

# --- Endpoint ---
resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.project_name}-fd-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

# --- Origin Groups ---
resource "azurerm_cdn_frontdoor_origin_group" "this" {
  for_each                 = { for bp in var.backend_pools : bp.name => bp }
  name                     = "${var.project_name}-${each.key}-og"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = each.value.session_affinity

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
    additional_latency_in_milliseconds = each.value.latency_sensitivity
  }

  health_probe {
    path                = each.value.health_probe_path
    protocol            = each.value.health_probe_protocol
    interval_in_seconds = 30
    request_type        = "HEAD"
  }
}

# --- Origins ---
resource "azurerm_cdn_frontdoor_origin" "this" {
  for_each                       = { for bp in var.backend_pools : bp.name => bp }
  name                           = "${var.project_name}-${each.key}-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this[each.key].id
  enabled                        = true
  host_name                      = each.value.host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = each.value.host_name
  certificate_name_check_enabled = true
  priority                       = each.value.priority
  weight                         = each.value.weight
}

# --- Routes ---
resource "azurerm_cdn_frontdoor_route" "this" {
  for_each                      = { for rr in var.routing_rules : rr.name => rr }
  name                          = "${var.project_name}-${each.key}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this[each.value.backend_pool].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this[each.value.backend_pool].id]
  patterns_to_match             = each.value.patterns_to_match
  supported_protocols           = ["Http", "Https"]
  https_redirect_enabled        = true
  forwarding_protocol           = each.value.forwarding_protocol

  dynamic "cache" {
    for_each = each.value.enable_caching ? [1] : []
    content {
      query_string_caching_behavior = "IgnoreQueryString"
      compression_enabled           = true
      content_types_to_compress     = ["text/html", "text/css", "application/javascript", "application/json", "image/svg+xml"]
    }
  }
}

# --- WAF Policy ---
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  count               = var.enable_waf ? 1 : 0
  name                = replace("${var.project_name}-fd-waf", "-", "")
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  enabled             = true
  mode                = var.waf_mode

  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-fd-waf" })
}

# --- WAF Security Policy ---
resource "azurerm_cdn_frontdoor_security_policy" "this" {
  count                    = var.enable_waf ? 1 : 0
  name                     = "${var.project_name}-fd-sec"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}
