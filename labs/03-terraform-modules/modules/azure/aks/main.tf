# ============================================================
# AKS Module — Azure Kubernetes Service with managed identity,
#   Azure CNI, RBAC, monitoring, auto-scaling, and Key Vault
# Author: Jenella Awo
# ============================================================

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.project_name}-aks-identity"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(var.tags, { Name = "${var.project_name}-aks-identity" })
}

resource "azurerm_kubernetes_cluster" "this" {
  name                    = "${var.project_name}-aks"
  location                = var.location
  resource_group_name     = var.resource_group_name
  dns_prefix              = "${var.project_name}-aks"
  kubernetes_version      = var.kubernetes_version
  private_cluster_enabled = var.private_cluster
  sku_tier                = var.sku_tier

  default_node_pool {
    name                = "system"
    node_count          = var.enable_auto_scaling ? null : var.system_node_count
    vm_size             = var.system_vm_size
    vnet_subnet_id      = var.vnet_subnet_id
    auto_scaling_enabled = var.enable_auto_scaling
    min_count           = var.enable_auto_scaling ? var.min_count : null
    max_count           = var.enable_auto_scaling ? var.max_count : null
    os_disk_size_gb     = var.os_disk_size_gb
    max_pods            = var.max_pods
    zones               = var.availability_zones

    tags = merge(var.tags, { Name = "${var.project_name}-aks-system-pool" })
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = var.network_policy
    load_balancer_sku = "standard"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_ad_rbac ? [1] : []
    content {
      azure_rbac_enabled = true
      tenant_id          = var.tenant_id
    }
  }

  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.enable_key_vault_secrets_provider ? [1] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = "2m"
    }
  }

  azure_policy_enabled = var.enable_azure_policy

  tags = merge(var.tags, { Name = "${var.project_name}-aks" })
}

# ------------------------------------
# User Node Pools
# ------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = { for pool in var.user_node_pools : pool.name => pool }

  name                  = each.value.name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = each.value.vm_size
  node_count            = lookup(each.value, "enable_auto_scaling", false) ? null : each.value.node_count
  auto_scaling_enabled  = lookup(each.value, "enable_auto_scaling", false)
  min_count             = lookup(each.value, "enable_auto_scaling", false) ? lookup(each.value, "min_count", 1) : null
  max_count             = lookup(each.value, "enable_auto_scaling", false) ? lookup(each.value, "max_count", 5) : null
  vnet_subnet_id        = var.vnet_subnet_id
  os_disk_size_gb       = lookup(each.value, "os_disk_size_gb", 128)
  max_pods              = lookup(each.value, "max_pods", 30)
  mode                  = lookup(each.value, "mode", "User")
  os_type               = lookup(each.value, "os_type", "Linux")
  zones                 = lookup(each.value, "zones", null)
  node_labels           = lookup(each.value, "labels", {})
  node_taints           = lookup(each.value, "taints", [])

  tags = merge(var.tags, { Name = "${var.project_name}-aks-${each.value.name}-pool" })
}
