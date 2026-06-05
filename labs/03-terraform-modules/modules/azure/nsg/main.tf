# ============================================================
# NSG Module — Network Security Group with configurable rules,
#   common presets, subnet associations, and flow logs
# Author: Jenella Awo
# ============================================================

resource "azurerm_network_security_group" "this" {
  name                = coalesce(var.nsg_name, "${var.project_name}-nsg")
  location            = var.location
  resource_group_name = var.resource_group_name

  # --- Inbound Rules ---
  dynamic "security_rule" {
    for_each = var.inbound_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = lookup(security_rule.value, "source_port_range", "*")
      destination_port_range     = lookup(security_rule.value, "destination_port_range", null)
      destination_port_ranges    = lookup(security_rule.value, "destination_port_ranges", null)
      source_address_prefix      = lookup(security_rule.value, "source_address_prefix", null)
      source_address_prefixes    = lookup(security_rule.value, "source_address_prefixes", null)
      destination_address_prefix = lookup(security_rule.value, "destination_address_prefix", "*")
    }
  }

  # --- Outbound Rules ---
  dynamic "security_rule" {
    for_each = var.outbound_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Outbound"
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = lookup(security_rule.value, "source_port_range", "*")
      destination_port_range     = lookup(security_rule.value, "destination_port_range", null)
      destination_port_ranges    = lookup(security_rule.value, "destination_port_ranges", null)
      source_address_prefix      = lookup(security_rule.value, "source_address_prefix", "*")
      destination_address_prefix = lookup(security_rule.value, "destination_address_prefix", null)
      destination_address_prefixes = lookup(security_rule.value, "destination_address_prefixes", null)
    }
  }

  # --- Preset: Allow Web Traffic ---
  dynamic "security_rule" {
    for_each = var.preset_web ? [1] : []
    content {
      name                       = "AllowHTTP"
      priority                   = 1000
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.preset_web ? [1] : []
    content {
      name                       = "AllowHTTPS"
      priority                   = 1001
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }

  # --- Preset: Allow SSH ---
  dynamic "security_rule" {
    for_each = var.preset_ssh ? [1] : []
    content {
      name                       = "AllowSSH"
      priority                   = 1010
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.ssh_source_address
      destination_address_prefix = "*"
    }
  }

  # --- Preset: Allow RDP ---
  dynamic "security_rule" {
    for_each = var.preset_rdp ? [1] : []
    content {
      name                       = "AllowRDP"
      priority                   = 1020
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.rdp_source_address
      destination_address_prefix = "*"
    }
  }

  # --- Preset: Allow Database ---
  dynamic "security_rule" {
    for_each = var.preset_database ? [1] : []
    content {
      name                       = "AllowSQL"
      priority                   = 1030
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["1433", "3306", "5432"]
      source_address_prefix      = var.database_source_address
      destination_address_prefix = "*"
    }
  }

  tags = merge(var.tags, { Name = coalesce(var.nsg_name, "${var.project_name}-nsg") })
}

# ------------------------------------
# Subnet Associations
# ------------------------------------
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = toset(var.subnet_ids)

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.this.id
}

# ------------------------------------
# NSG Flow Logs
# ------------------------------------
resource "azurerm_network_watcher_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  name                      = "${var.project_name}-nsg-flow-log"
  network_watcher_name      = var.network_watcher_name
  resource_group_name       = var.network_watcher_resource_group
  network_security_group_id = azurerm_network_security_group.this.id
  storage_account_id        = var.storage_account_id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  dynamic "traffic_analytics" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    content {
      enabled               = true
      workspace_id          = var.log_analytics_workspace_guid
      workspace_region      = var.location
      workspace_resource_id = var.log_analytics_workspace_id
      interval_in_minutes   = 10
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-nsg-flow-log" })
}
