# ============================================================
# SQL Database Module — Outputs
# Author: Jenella Awo
# ============================================================

output "server_id" {
  description = "The ID of the Azure SQL Server"
  value       = azurerm_mssql_server.this.id
}

output "server_fqdn" {
  description = "The fully qualified domain name of the Azure SQL Server"
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_id" {
  description = "The ID of the SQL database"
  value       = azurerm_mssql_database.this.id
}

output "database_name" {
  description = "The name of the SQL database"
  value       = azurerm_mssql_database.this.name
}

output "connection_string" {
  description = "ADO.NET connection string for the SQL database"
  value       = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.this.name};Persist Security Info=False;User ID=${var.administrator_login};Password=${var.administrator_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  sensitive   = true
}
