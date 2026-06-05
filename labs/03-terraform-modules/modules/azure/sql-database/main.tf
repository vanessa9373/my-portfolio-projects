# ============================================================
# SQL Database Module — Azure SQL Server and Database with
#   AD admin, firewall, TDE, auditing, geo-replication,
#   private endpoint, and long-term backup retention
# Author: Jenella Awo
# ============================================================

resource "azurerm_mssql_server" "this" {
  name                         = "${var.project_name}-sqlserver"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password
  minimum_tls_version          = "1.2"

  dynamic "azuread_administrator" {
    for_each = var.azuread_admin != null ? [var.azuread_admin] : []
    content {
      login_username = azuread_administrator.value.login_username
      object_id      = azuread_administrator.value.object_id
      tenant_id      = lookup(azuread_administrator.value, "tenant_id", null)
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, { Name = "${var.project_name}-sqlserver" })
}

# ------------------------------------
# Primary Database
# ------------------------------------
resource "azurerm_mssql_database" "this" {
  name                        = "${var.project_name}-sqldb"
  server_id                   = azurerm_mssql_server.this.id
  sku_name                    = var.sku_name
  max_size_gb                 = var.max_size_gb
  collation                   = var.collation
  zone_redundant              = var.zone_redundant
  read_scale                  = var.sku_name == "P1" || var.sku_name == "P2" || var.sku_name == "P4" || var.sku_name == "P6" || var.sku_name == "P11" || var.sku_name == "P15" ? true : false
  transparent_data_encryption_enabled = true

  long_term_retention_policy {
    weekly_retention  = var.ltr_weekly_retention
    monthly_retention = var.ltr_monthly_retention
    yearly_retention  = var.ltr_yearly_retention
    week_of_year      = var.ltr_week_of_year
  }

  short_term_retention_policy {
    retention_days           = var.short_term_retention_days
    backup_interval_in_hours = 12
  }

  tags = merge(var.tags, { Name = "${var.project_name}-sqldb" })
}

# ------------------------------------
# Firewall Rules
# ------------------------------------
resource "azurerm_mssql_firewall_rule" "this" {
  for_each = { for rule in var.firewall_rules : rule.name => rule }

  name             = each.value.name
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

# Allow Azure services
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ------------------------------------
# Auditing
# ------------------------------------
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  count = var.enable_auditing ? 1 : 0

  server_id                               = azurerm_mssql_server.this.id
  storage_endpoint                        = var.storage_account_primary_blob_endpoint
  storage_account_access_key              = var.storage_account_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = var.audit_retention_days
  log_monitoring_enabled                  = true
}

# ------------------------------------
# Geo-Replication
# ------------------------------------
resource "azurerm_mssql_server" "secondary" {
  count = var.enable_geo_replication ? 1 : 0

  name                         = "${var.project_name}-sqlserver-secondary"
  location                     = var.geo_location
  resource_group_name          = var.resource_group_name
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password
  minimum_tls_version          = "1.2"

  tags = merge(var.tags, { Name = "${var.project_name}-sqlserver-secondary" })
}

resource "azurerm_mssql_failover_group" "this" {
  count = var.enable_geo_replication ? 1 : 0

  name      = "${var.project_name}-sql-failover"
  server_id = azurerm_mssql_server.this.id

  partner_server {
    id = azurerm_mssql_server.secondary[0].id
  }

  read_write_endpoint_failover_policy {
    mode          = "Automatic"
    grace_minutes = 60
  }

  databases = [azurerm_mssql_database.this.id]

  tags = merge(var.tags, { Name = "${var.project_name}-sql-failover" })
}

# ------------------------------------
# Private Endpoint
# ------------------------------------
resource "azurerm_private_endpoint" "sql" {
  count = var.subnet_id != null ? 1 : 0

  name                = "${var.project_name}-sql-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "${var.project_name}-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.this.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-sql-pe" })
}
