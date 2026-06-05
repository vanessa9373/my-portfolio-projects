# ============================================================
# Azure Redis Cache Module — Azure Cache for Redis
# Author: Jenella Awo
# ============================================================

resource "azurerm_redis_cache" "this" {
  name                          = "${var.project_name}-redis"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  capacity                      = var.capacity
  family                        = var.family
  sku_name                      = var.sku_name
  enable_non_ssl_port           = var.enable_non_ssl
  minimum_tls_version           = var.minimum_tls_version
  public_network_access_enabled = var.subnet_id == null ? true : false
  subnet_id                     = var.subnet_id

  redis_configuration {
    maxmemory_reserved              = var.redis_configuration.maxmemory_reserved
    maxmemory_delta                 = var.redis_configuration.maxmemory_delta
    maxmemory_policy                = var.redis_configuration.maxmemory_policy
    maxfragmentationmemory_reserved = var.redis_configuration.maxfragmentationmemory_reserved
    rdb_backup_enabled              = var.sku_name == "Premium" ? var.redis_configuration.rdb_backup_enabled : false
    rdb_backup_frequency            = var.sku_name == "Premium" && var.redis_configuration.rdb_backup_enabled ? var.redis_configuration.rdb_backup_frequency : null
    rdb_backup_max_snapshot_count   = var.sku_name == "Premium" && var.redis_configuration.rdb_backup_enabled ? var.redis_configuration.rdb_backup_max_snapshot_count : null
    rdb_storage_connection_string   = var.sku_name == "Premium" && var.redis_configuration.rdb_backup_enabled ? var.redis_configuration.rdb_storage_connection_string : null
  }

  dynamic "patch_schedule" {
    for_each = var.patch_schedule != null ? [var.patch_schedule] : []
    content {
      day_of_week        = patch_schedule.value.day_of_week
      start_hour_utc     = patch_schedule.value.start_hour_utc
      maintenance_window = patch_schedule.value.maintenance_window
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-redis" })
}

# --- Firewall Rules ---
resource "azurerm_redis_firewall_rule" "this" {
  for_each            = { for rule in var.firewall_rules : rule.name => rule }
  name                = each.value.name
  redis_cache_name    = azurerm_redis_cache.this.name
  resource_group_name = var.resource_group_name
  start_ip            = each.value.start_ip
  end_ip              = each.value.end_ip
}
