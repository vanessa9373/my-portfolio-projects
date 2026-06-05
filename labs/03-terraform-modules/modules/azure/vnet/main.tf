# ============================================================
# VNet Module — Azure Virtual Network with subnets, NSGs,
#   service endpoints, peering, and optional DDoS protection
# Author: Jenella Awo
# ============================================================

resource "azurerm_network_ddos_protection_plan" "this" {
  count = var.enable_ddos ? 1 : 0

  name                = "${var.project_name}-ddos-plan"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, { Name = "${var.project_name}-ddos-plan" })
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.project_name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space

  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.this[0].id
      enable = true
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-vnet" })
}

# ------------------------------------
# Subnets
# ------------------------------------
resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "${var.project_name}-${each.key}-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = lookup(each.value, "service_endpoints", [])

  dynamic "delegation" {
    for_each = lookup(each.value, "delegation", null) != null ? [each.value.delegation] : []
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_name
        actions = lookup(delegation.value, "actions", [])
      }
    }
  }
}

# ------------------------------------
# Network Security Groups per subnet
# ------------------------------------
resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "${var.project_name}-${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, { Name = "${var.project_name}-${each.key}-nsg" })
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# ------------------------------------
# VNet Peering (optional)
# ------------------------------------
resource "azurerm_virtual_network_peering" "this" {
  for_each = var.vnet_peerings

  name                         = "${var.project_name}-peer-${each.key}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = each.value.remote_vnet_id
  allow_virtual_network_access = lookup(each.value, "allow_vnet_access", true)
  allow_forwarded_traffic      = lookup(each.value, "allow_forwarded_traffic", false)
  allow_gateway_transit        = lookup(each.value, "allow_gateway_transit", false)
  use_remote_gateways          = lookup(each.value, "use_remote_gateways", false)
}
