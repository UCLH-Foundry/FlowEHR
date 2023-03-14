#  Copyright (c) University College London Hospitals NHS Foundation Trust
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

resource "random_password" "sql_admin_password" {
  length  = 16
  special = true
}

# AAD App + secret to set as AAD Admin of SQL Server
resource "azuread_application" "flowehr_sql_owner" {
  display_name = local.sql_owner_app_name
  owners       = [data.azurerm_client_config.current.object_id]
}
resource "azuread_application_password" "flowehr_sql_owner" {
  application_object_id = azuread_application.flowehr_sql_owner.object_id
}
resource "azuread_service_principal" "flowehr_sql_owner" {
  application_id = azuread_application.flowehr_sql_owner.application_id
  owners         = [data.azurerm_client_config.current.object_id]
}

# Azure SQL logical server, public access disabled - will use private endpoints for access
resource "azurerm_mssql_server" "sql_server_features" {
  name                                 = "sql-server-features-${lower(var.naming_suffix)}"
  location                             = var.core_rg_location
  resource_group_name                  = var.core_rg_name
  version                              = "12.0"
  administrator_login                  = local.sql_server_features_admin_username
  administrator_login_password         = random_password.sql_admin_password.result
  public_network_access_enabled        = var.local_mode
  outbound_network_restriction_enabled = true
  tags                                 = var.tags
  azuread_administrator {
    login_username = local.sql_owner_app_name
    object_id      = azuread_service_principal.flowehr_sql_owner.object_id
  }
  identity {
    type = "SystemAssigned"
  }
}

# Assign the SQL Identity User.Read.All / GroupMember.Read.All / Application.Read.All
# Doc here: https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity
resource "azuread_service_principal" "msgraph" {
  application_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
  use_existing   = true
}

resource "azuread_app_role_assignment" "sql_user_read_all" {
  app_role_id         = azuread_service_principal.msgraph.app_role_ids["User.Read.All"]
  principal_object_id = azurerm_mssql_server.sql_server_features.identity[0].principal_id
  resource_object_id  = azuread_service_principal.msgraph.object_id
}
resource "azuread_app_role_assignment" "sql_groupmember_read_all" {
  app_role_id         = azuread_service_principal.msgraph.app_role_ids["GroupMember.Read.All"]
  principal_object_id = azurerm_mssql_server.sql_server_features.identity[0].principal_id
  resource_object_id  = azuread_service_principal.msgraph.object_id
}
resource "azuread_app_role_assignment" "sql_application_read_all" {
  app_role_id         = azuread_service_principal.msgraph.app_role_ids["Application.Read.All"]
  principal_object_id = azurerm_mssql_server.sql_server_features.identity[0].principal_id
  resource_object_id  = azuread_service_principal.msgraph.object_id
}

# optional firewall rule when running in local_mode
resource "azurerm_mssql_firewall_rule" "deployer_ip_exception" {
  count            = var.local_mode == true ? 1 : 0
  name             = "DeployerIP"
  server_id        = azurerm_mssql_server.sql_server_features.id
  start_ip_address = var.deployer_ip_address
  end_ip_address   = var.deployer_ip_address
}

# Enable Transparent Data Encryption (TDE) with a Service Managed Key
resource "azurerm_mssql_server_transparent_data_encryption" "sql_server_features_encryption" {
  server_id = azurerm_mssql_server.sql_server_features.id
}

# Azure SQL database, basic + small for dev
# TODO: Rightsize for prod -> https://github.com/UCLH-Foundry/FlowEHR/issues/63
resource "azurerm_mssql_database" "feature_database" {
  name                 = "sql-db-features"
  server_id            = azurerm_mssql_server.sql_server_features.id
  collation            = "SQL_Latin1_General_CP1_CI_AS"
  license_type         = "LicenseIncluded"
  max_size_gb          = 2
  sku_name             = "Basic"
  storage_account_type = "Local"
  zone_redundant       = false
  tags                 = var.tags
}

resource "null_resource" "create_sql_user" {
  # make sure we have the identity created with aad perms, a client + secret to connect with, and an identity to set as dbo
  depends_on = [
    azuread_application_password.flowehr_sql_owner,
    azuread_application.flowehr_databricks_sql,
    azuread_app_role_assignment.sql_user_read_all,
    azuread_app_role_assignment.sql_groupmember_read_all,
    azuread_app_role_assignment.sql_application_read_all,
    azurerm_private_endpoint.sql_server_features_pe
  ]

  triggers = {
    app_name      = azuread_application.flowehr_databricks_sql.display_name
    database_name = azurerm_mssql_database.feature_database.name
  }

  # set the databricks 'user' app as dbo on the flowehr database
  # load a csv file into a new SQL table
  provisioner "local-exec" {
    command = <<EOF
      SCRIPTS_DIR="../../scripts"
      $SCRIPTS_DIR/retry.sh python $SCRIPTS_DIR/sql/create_sql_user.py
      $SCRIPTS_DIR/retry.sh python $SCRIPTS_DIR/sql/load_csv_data.py
    EOF
    environment = {
      SERVER          = azurerm_mssql_server.sql_server_features.fully_qualified_domain_name
      DATABASE        = azurerm_mssql_database.feature_database.name
      CLIENT_ID       = azuread_application.flowehr_sql_owner.application_id
      CLIENT_SECRET   = azuread_application_password.flowehr_sql_owner.value
      USERS_TO_CREATE = jsonencode(local.sql_users_to_create)
      PATH_TO_CSV     = "../../scripts/sql/nhsd-diabetes.csv"
      TABLE_NAME      = "deploy-test-diabetes"
    }
  }
}

# AAD App + SPN for Databricks -> SQL Access
resource "azuread_application" "flowehr_databricks_sql" {
  display_name = local.databricks_app_name
  owners       = [data.azurerm_client_config.current.object_id]
}
resource "azuread_application_password" "flowehr_databricks_sql" {
  application_object_id = azuread_application.flowehr_databricks_sql.object_id
}
resource "azuread_service_principal" "flowehr_databricks_sql" {
  application_id = azuread_application.flowehr_databricks_sql.application_id
  owners         = [data.azurerm_client_config.current.object_id]
}

# Push secrets to KV
resource "azurerm_key_vault_secret" "sql_server_owner_app_id" {
  name         = "sql-owner-app-id"
  value        = azuread_application.flowehr_sql_owner.application_id
  key_vault_id = var.core_kv_id
}
resource "azurerm_key_vault_secret" "sql_server_owner_secret" {
  name         = "sql-owner-secret"
  value        = azuread_application_password.flowehr_sql_owner.value
  key_vault_id = var.core_kv_id
}
resource "azurerm_key_vault_secret" "sql_server_features_admin_username" {
  name         = "sql-features-admin-username"
  value        = local.sql_server_features_admin_username
  key_vault_id = var.core_kv_id
}
resource "azurerm_key_vault_secret" "sql_server_features_admin_password" {
  name         = "sql-features-admin-password"
  value        = random_password.sql_admin_password.result
  key_vault_id = var.core_kv_id
}
resource "azurerm_key_vault_secret" "flowehr_databricks_sql_spn_app_id" {
  name         = "flowehr-dbks-sql-app-id"
  value        = azuread_service_principal.flowehr_databricks_sql.application_id
  key_vault_id = var.core_kv_id
}
resource "azurerm_key_vault_secret" "flowehr_databricks_sql_spn_app_secret" {
  name         = "flowehr-dbks-sql-app-secret"
  value        = azuread_application_password.flowehr_databricks_sql.value
  key_vault_id = var.core_kv_id
}

# Private DNS + endpoint for SQL Server
resource "azurerm_private_dns_zone" "sql" {
  name                = "privatelink.database.windows.net"
  resource_group_name = var.core_rg_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name                  = "vnl-sql-${var.naming_suffix}"
  resource_group_name   = var.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  virtual_network_id    = data.azurerm_virtual_network.core.id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "sql_server_features_pe" {
  name                = "pe-sql-feature-data-${var.naming_suffix}"
  resource_group_name = var.core_rg_name
  location            = var.core_rg_location
  subnet_id           = var.core_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "private-service-connection-sql-feature-data-${var.naming_suffix}"
    private_connection_resource_id = azurerm_mssql_server.sql_server_features.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-group-sql-${var.naming_suffix}"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

resource "azuread_group" "ad_group_apps" {
  display_name     = "${var.naming_suffix} flowehr-apps"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
}

resource "azuread_group" "ad_group_developers" {
  display_name     = "${var.naming_suffix} flowehr-developers"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
}

resource "azuread_group" "ad_group_data_scientists" {
  display_name     = "${var.naming_suffix} flowehr-data-scientists"
  owners           = [data.azurerm_client_config.current.object_id]
  security_enabled = true
}

output "apps_ad_group_display_name" {
  description = "Apps AD group display name"
  value       = azuread_group.ad_group_apps.display_name
}

output "developers_ad_group_display_name" {
  description = "Apps AD group display name"
  value       = azuread_group.ad_group_developers.display_name
}

output "apps_ad_group_principal_id" {
  description = "Apps AD group principal id "
  value       = azuread_group.ad_group_apps.object_id
}

output "developers_ad_group_principal_id" {
  description = "Developers AD group principal id "
  value       = azuread_group.ad_group_developers.object_id
}
