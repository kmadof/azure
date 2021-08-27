provider "azurerm" {
  features {}
}

variable "administrator_login" {}
variable "administrator_login_password" {}

resource "azurerm_resource_group" "martello" {
  name     = "martello-rg"
  location = "west europe"
}

resource "azurerm_virtual_network" "martello_vnet" {
  name                = "martello-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.martello.location
  resource_group_name = azurerm_resource_group.martello.name
}

resource "azurerm_subnet" "martello_subnet" {
  name                 = "api"
  resource_group_name  = azurerm_resource_group.martello.name
  virtual_network_name = azurerm_virtual_network.martello_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints    = ["Microsoft.Sql"]

  delegation {
    name = "martellodelegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_application_insights" "martello" {
  name                = "martello-appinsights"
  location            = azurerm_resource_group.martello.location
  resource_group_name = azurerm_resource_group.martello.name
  application_type    = "web"
}

resource "azurerm_app_service_plan" "martello_app_plan" {
  name                = "martelloplan"
  location            = azurerm_resource_group.martello.location
  resource_group_name = azurerm_resource_group.martello.name

  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_storage_account" "martello_st" {
  name                     = "martellost"
  resource_group_name      = azurerm_resource_group.martello.name
  location                 = azurerm_resource_group.martello.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_function_app" "martello_func" {
  name                       = "martello-func"
  location                   = azurerm_resource_group.martello.location
  resource_group_name        = azurerm_resource_group.martello.name
  app_service_plan_id        = azurerm_app_service_plan.martello_app_plan.id
  storage_account_name       = azurerm_storage_account.martello_st.name
  storage_account_access_key = azurerm_storage_account.martello_st.primary_access_key

  version = "~3"

  site_config {
    use_32_bit_worker_process = false
    always_on                 = true
    dotnet_framework_version  = "v5.0"
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "dotnet-isolated"
    FUNCTIONS_EXTENSION_VERSION    = "~3"
    ASPNETCORE_ENVIRONMENT         = "Production"
    sqldb_connection               = "Server=tcp:${azurerm_mssql_server.martello_sql_server.fully_qualified_domain_name};Initial Catalog=${azurerm_mssql_database.martello_sql_db.name};Persist Security Info=False;User ID=${var.administrator_login};Password=${var.administrator_login_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.martello.instrumentation_key
  }
}

resource "azurerm_app_service_virtual_network_swift_connection" "example" {
  app_service_id = azurerm_function_app.martello_func.id
  subnet_id      = azurerm_subnet.martello_subnet.id
}

resource "azurerm_mssql_server" "martello_sql_server" {
  name                         = "martello-sqlserver"
  resource_group_name          = azurerm_resource_group.martello.name
  location                     = azurerm_resource_group.martello.location
  version                      = "12.0"
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_login_password
}

resource "azurerm_mssql_database" "martello_sql_db" {
  name           = "martello-db"
  server_id      = azurerm_mssql_server.martello_sql_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 4
  read_scale     = true
  sku_name       = "BC_Gen5_2"
  zone_redundant = true

  tags = {
    foo = "bar"
  }
}

resource "azurerm_mssql_database_extended_auditing_policy" "martello_sql_db_policy" {
  database_id                             = azurerm_mssql_database.martello_sql_db.id
  storage_endpoint                        = azurerm_storage_account.martello_st.primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.martello_st.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
}

resource "azurerm_mssql_virtual_network_rule" "martello_sql_server_rule" {
  name      = "sql-vnet-rule"
  server_id = azurerm_mssql_server.martello_sql_server.id
  subnet_id = azurerm_subnet.martello_subnet.id
}