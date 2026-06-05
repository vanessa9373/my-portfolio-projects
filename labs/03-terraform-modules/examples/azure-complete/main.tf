# ============================================================
# Azure Complete Example — Using All Azure Modules Together
# Author: Jenella Awo
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.80" }
  }
}

provider "azurerm" {
  features {}
}

# --- Data Sources ---
data "azurerm_client_config" "current" {}

# --- Resource Group ---
resource "azurerm_resource_group" "this" {
  name     = "${var.project_name}-rg"
  location = var.location
  tags     = local.tags
}

locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- Networking ---
module "vnet" {
  source              = "../../modules/azure/vnet"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.0.0.0/16"]
  subnets = {
    aks = {
      address_prefix    = "10.0.1.0/24"
      service_endpoints = ["Microsoft.Sql", "Microsoft.Storage"]
      delegation        = null
    }
    database = {
      address_prefix    = "10.0.2.0/24"
      service_endpoints = ["Microsoft.Sql"]
      delegation        = null
    }
    appgw = {
      address_prefix    = "10.0.3.0/24"
      service_endpoints = []
      delegation        = null
    }
    functions = {
      address_prefix    = "10.0.4.0/24"
      service_endpoints = ["Microsoft.Storage"]
      delegation = {
        name = "functions"
        service_delegation = {
          name    = "Microsoft.Web/serverFarms"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }
  }
  tags = local.tags
}

module "nsg" {
  source              = "../../modules/azure/nsg"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  nsg_name            = "aks"
  inbound_rules = [
    {
      name                       = "allow-https"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
  outbound_rules = []
  tags           = local.tags
}

# --- AKS Cluster ---
module "aks" {
  source              = "../../modules/azure/aks"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  kubernetes_version  = "1.29"
  vnet_subnet_id      = module.vnet.subnet_ids["aks"]
  system_node_count   = 2
  system_vm_size      = "Standard_D4s_v3"
  enable_auto_scaling = true
  min_count           = 2
  max_count           = 10
  tags                = local.tags
}

# --- SQL Database ---
module "sql" {
  source              = "../../modules/azure/sql-database"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  administrator_login = "sqladmin"
  administrator_password = var.db_password
  sku_name            = "S1"
  max_size_gb         = 50
  subnet_id           = module.vnet.subnet_ids["database"]
  tags                = local.tags
}

# --- Storage Account ---
module "storage" {
  source                   = "../../modules/azure/storage-account"
  project_name             = var.project_name
  location                 = var.location
  resource_group_name      = azurerm_resource_group.this.name
  account_tier             = "Standard"
  account_replication_type = "GRS"
  containers               = ["uploads", "backups", "logs"]
  tags                     = local.tags
}

# --- Key Vault ---
module "key_vault" {
  source              = "../../modules/azure/key-vault"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

# --- Container Registry ---
module "acr" {
  source              = "../../modules/azure/acr"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Premium"
  admin_enabled       = false
  tags                = local.tags
}

# --- Redis Cache ---
module "redis" {
  source              = "../../modules/azure/redis-cache"
  project_name        = var.project_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Standard"
  family              = "C"
  capacity            = 1
  tags                = local.tags
}

# --- DNS ---
module "dns" {
  source              = "../../modules/azure/dns"
  project_name        = var.project_name
  resource_group_name = azurerm_resource_group.this.name
  domain_name         = var.domain_name
  records = [
    { name = "app",  type = "A",     ttl = 300, values = ["10.0.1.100"] },
    { name = "api",  type = "CNAME", ttl = 300, values = ["api.${var.domain_name}"] },
  ]
  tags = local.tags
}

# --- Variables ---
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "demo-app"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US 2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "db_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for DNS zone"
  type        = string
  default     = "example.com"
}

# --- Outputs ---
output "aks_cluster_name"   { value = module.aks.cluster_name }
output "sql_server_fqdn"    { value = module.sql.server_fqdn }
output "storage_endpoint"   { value = module.storage.primary_blob_endpoint }
output "key_vault_uri"      { value = module.key_vault.vault_uri }
output "acr_login_server"   { value = module.acr.login_server }
output "redis_hostname"     { value = module.redis.hostname }
