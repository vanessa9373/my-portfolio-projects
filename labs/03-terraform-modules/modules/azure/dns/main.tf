# ============================================================
# Azure DNS Module — Public & Private DNS Zones
# Author: Jenella Awo
# ============================================================

# --- Public DNS Zone ---
resource "azurerm_dns_zone" "public" {
  count               = var.private_zone ? 0 : 1
  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { Name = "${var.project_name}-dns" })
}

# --- Private DNS Zone ---
resource "azurerm_private_dns_zone" "private" {
  count               = var.private_zone ? 1 : 0
  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { Name = "${var.project_name}-private-dns" })
}

# --- VNet Link (Private Zone) ---
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  count                 = var.private_zone && var.vnet_id != null ? 1 : 0
  name                  = "${var.project_name}-vnet-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.private[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = var.enable_auto_registration
  tags                  = var.tags
}

# --- Public A Records ---
resource "azurerm_dns_a_record" "this" {
  for_each = {
    for r in var.records : r.name => r if r.type == "A" && !var.private_zone
  }
  name                = each.value.name
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  records             = each.value.values
  tags                = var.tags
}

# --- Public CNAME Records ---
resource "azurerm_dns_cname_record" "this" {
  for_each = {
    for r in var.records : r.name => r if r.type == "CNAME" && !var.private_zone
  }
  name                = each.value.name
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  record              = each.value.values[0]
  tags                = var.tags
}

# --- Public MX Records ---
resource "azurerm_dns_mx_record" "this" {
  for_each = {
    for r in var.records : r.name => r if r.type == "MX" && !var.private_zone
  }
  name                = each.value.name
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl

  dynamic "record" {
    for_each = each.value.values
    content {
      preference = split(" ", record.value)[0]
      exchange   = split(" ", record.value)[1]
    }
  }

  tags = var.tags
}

# --- Public TXT Records ---
resource "azurerm_dns_txt_record" "this" {
  for_each = {
    for r in var.records : r.name => r if r.type == "TXT" && !var.private_zone
  }
  name                = each.value.name
  zone_name           = azurerm_dns_zone.public[0].name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl

  dynamic "record" {
    for_each = each.value.values
    content {
      value = record.value
    }
  }

  tags = var.tags
}

# --- Private A Records ---
resource "azurerm_private_dns_a_record" "this" {
  for_each = {
    for r in var.records : r.name => r if r.type == "A" && var.private_zone
  }
  name                  = each.value.name
  zone_name             = azurerm_private_dns_zone.private[0].name
  resource_group_name   = var.resource_group_name
  ttl                   = each.value.ttl
  records               = each.value.values
  tags                  = var.tags
}
