# ============================================================
# Storage Account Module — Azure Storage with blob containers,
#   file shares, lifecycle management, network rules, CMK
#   encryption, and static website hosting
# Author: Jenella Awo
# ============================================================

resource "azurerm_storage_account" "this" {
  name                            = replace(lower("${var.project_name}sa"), "-", "")
  location                        = var.location
  resource_group_name             = var.resource_group_name
  account_tier                    = var.account_tier
  account_replication_type        = var.account_replication_type
  account_kind                    = var.account_kind
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only       = true

  dynamic "identity" {
    for_each = var.cmk_key_vault_key_id != null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.cmk_key_vault_key_id != null ? [1] : []
    content {
      key_vault_key_id          = var.cmk_key_vault_key_id
      user_assigned_identity_id = null
    }
  }

  blob_properties {
    versioning_enabled       = var.enable_versioning
    change_feed_enabled      = var.enable_change_feed
    last_access_time_enabled = true

    dynamic "delete_retention_policy" {
      for_each = var.blob_soft_delete_days > 0 ? [1] : []
      content {
        days = var.blob_soft_delete_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.container_soft_delete_days > 0 ? [1] : []
      content {
        days = var.container_soft_delete_days
      }
    }
  }

  dynamic "static_website" {
    for_each = var.enable_static_website ? [1] : []
    content {
      index_document     = var.index_document
      error_404_document = var.error_404_document
    }
  }

  dynamic "network_rules" {
    for_each = var.network_rules != null ? [var.network_rules] : []
    content {
      default_action             = network_rules.value.default_action
      bypass                     = lookup(network_rules.value, "bypass", ["AzureServices"])
      ip_rules                   = lookup(network_rules.value, "ip_rules", [])
      virtual_network_subnet_ids = lookup(network_rules.value, "virtual_network_subnet_ids", [])
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-storage" })
}

# ------------------------------------
# Blob Containers
# ------------------------------------
resource "azurerm_storage_container" "this" {
  for_each = { for c in var.containers : c.name => c }

  name                  = each.value.name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = lookup(each.value, "access_type", "private")
}

# ------------------------------------
# File Shares
# ------------------------------------
resource "azurerm_storage_share" "this" {
  for_each = { for s in var.file_shares : s.name => s }

  name               = each.value.name
  storage_account_id = azurerm_storage_account.this.id
  quota              = lookup(each.value, "quota", 50)
  access_tier        = lookup(each.value, "access_tier", "TransactionOptimized")
}

# ------------------------------------
# Lifecycle Management
# ------------------------------------
resource "azurerm_storage_management_policy" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  storage_account_id = azurerm_storage_account.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      name    = rule.value.name
      enabled = lookup(rule.value, "enabled", true)

      filters {
        blob_types   = lookup(rule.value, "blob_types", ["blockBlob"])
        prefix_match = lookup(rule.value, "prefix_match", [])
      }

      actions {
        base_blob {
          tier_to_cool_after_days_since_modification_greater_than    = lookup(rule.value, "tier_to_cool_days", null)
          tier_to_archive_after_days_since_modification_greater_than = lookup(rule.value, "tier_to_archive_days", null)
          delete_after_days_since_modification_greater_than          = lookup(rule.value, "delete_after_days", null)
        }
        snapshot {
          delete_after_days_since_creation_greater_than = lookup(rule.value, "snapshot_delete_days", null)
        }
      }
    }
  }
}
