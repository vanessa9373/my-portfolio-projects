# ============================================================
# Azure Function App Module — Serverless Functions
# Author: Jenella Awo
# ============================================================

# --- Linux Function App ---
resource "azurerm_linux_function_app" "this" {
  name                       = "${var.project_name}-func"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = var.service_plan_id
  storage_account_name       = var.storage_account_name
  storage_account_access_key = var.storage_account_access_key

  site_config {
    always_on                              = var.always_on
    application_insights_connection_string = var.enable_app_insights ? azurerm_application_insights.this[0].connection_string : null
    application_insights_key               = var.enable_app_insights ? azurerm_application_insights.this[0].instrumentation_key : null

    application_stack {
      node_version   = var.runtime_stack == "node" ? var.runtime_version : null
      python_version = var.runtime_stack == "python" ? var.runtime_version : null
      java_version   = var.runtime_stack == "java" ? var.runtime_version : null
      dotnet_version = var.runtime_stack == "dotnet" ? var.runtime_version : null
    }

    dynamic "cors" {
      for_each = var.cors_allowed_origins != null ? [1] : []
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
  }

  app_settings = merge(var.app_settings, {
    FUNCTIONS_WORKER_RUNTIME = var.runtime_stack
  })

  identity {
    type = "SystemAssigned"
  }

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }

  virtual_network_subnet_id = var.vnet_subnet_id

  tags = merge(var.tags, { Name = "${var.project_name}-func" })
}

# --- Application Insights ---
resource "azurerm_application_insights" "this" {
  count               = var.enable_app_insights ? 1 : 0
  name                = "${var.project_name}-func-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  retention_in_days   = 30
  tags                = merge(var.tags, { Name = "${var.project_name}-func-insights" })
}
