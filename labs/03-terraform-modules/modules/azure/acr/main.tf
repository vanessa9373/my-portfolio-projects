# ============================================================
# ACR Module — Azure Container Registry with geo-replication,
#   content trust, network rules, retention, and webhooks
# Author: Jenella Awo
# ============================================================

resource "azurerm_container_registry" "this" {
  name                = replace(lower("${var.project_name}acr"), "-", "")
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = var.admin_enabled

  dynamic "georeplications" {
    for_each = var.sku == "Premium" ? var.georeplications : []
    content {
      location                = georeplications.value.location
      zone_redundancy_enabled = lookup(georeplications.value, "zone_redundancy_enabled", false)
      tags                    = merge(var.tags, { Name = "${var.project_name}-acr-${georeplications.value.location}" })
    }
  }

  dynamic "retention_policy" {
    for_each = var.sku == "Premium" ? [1] : []
    content {
      days    = var.retention_days
      enabled = true
    }
  }

  trust_policy_enabled = var.sku == "Premium" ? var.enable_content_trust : false

  dynamic "network_rule_set" {
    for_each = var.sku == "Premium" && var.network_rule_set != null ? [var.network_rule_set] : []
    content {
      default_action = lookup(network_rule_set.value, "default_action", "Allow")

      dynamic "ip_rule" {
        for_each = lookup(network_rule_set.value, "ip_rules", [])
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }

      dynamic "virtual_network" {
        for_each = lookup(network_rule_set.value, "virtual_network_subnet_ids", [])
        content {
          action    = "Allow"
          subnet_id = virtual_network.value
        }
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-acr" })
}

# ------------------------------------
# Webhooks
# ------------------------------------
resource "azurerm_container_registry_webhook" "this" {
  for_each = { for wh in var.webhooks : wh.name => wh }

  name                = each.value.name
  resource_group_name = var.resource_group_name
  registry_name       = azurerm_container_registry.this.name
  location            = var.location
  service_uri         = each.value.service_uri
  actions             = each.value.actions
  status              = lookup(each.value, "status", "enabled")
  scope               = lookup(each.value, "scope", "")
  custom_headers      = lookup(each.value, "custom_headers", {})

  tags = merge(var.tags, { Name = "${var.project_name}-acr-webhook-${each.value.name}" })
}
