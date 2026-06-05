# ============================================================
# Key Vault Module — Azure Key Vault with access policies,
#   RBAC, network ACLs, soft delete, purge protection,
#   private endpoint, and diagnostic settings
# Author: Jenella Awo
# ============================================================

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                        = "${var.project_name}-kv"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = coalesce(var.tenant_id, data.azurerm_client_config.current.tenant_id)
  sku_name                    = var.sku_name
  enabled_for_deployment      = var.enabled_for_deployment
  enabled_for_disk_encryption = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  soft_delete_retention_days  = var.soft_delete_retention_days
  purge_protection_enabled    = var.enable_purge_protection
  enable_rbac_authorization   = var.enable_rbac

  dynamic "access_policy" {
    for_each = var.enable_rbac ? [] : var.access_policies
    content {
      tenant_id               = coalesce(lookup(access_policy.value, "tenant_id", null), var.tenant_id, data.azurerm_client_config.current.tenant_id)
      object_id               = access_policy.value.object_id
      key_permissions         = lookup(access_policy.value, "key_permissions", [])
      secret_permissions      = lookup(access_policy.value, "secret_permissions", [])
      certificate_permissions = lookup(access_policy.value, "certificate_permissions", [])
      storage_permissions     = lookup(access_policy.value, "storage_permissions", [])
    }
  }

  dynamic "network_acls" {
    for_each = var.network_acls != null ? [var.network_acls] : []
    content {
      default_action             = network_acls.value.default_action
      bypass                     = lookup(network_acls.value, "bypass", "AzureServices")
      ip_rules                   = lookup(network_acls.value, "ip_rules", [])
      virtual_network_subnet_ids = lookup(network_acls.value, "virtual_network_subnet_ids", [])
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-kv" })
}

# ------------------------------------
# Private Endpoint
# ------------------------------------
resource "azurerm_private_endpoint" "kv" {
  count = var.subnet_id != null ? 1 : 0

  name                = "${var.project_name}-kv-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.project_name}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-kv-pe" })
}

# ------------------------------------
# Diagnostic Settings
# ------------------------------------
resource "azurerm_monitor_diagnostic_setting" "kv" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "${var.project_name}-kv-diag"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
