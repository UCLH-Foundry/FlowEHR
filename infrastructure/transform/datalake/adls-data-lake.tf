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

# Create Azure Data Lake Gen2 store with bronze, silver and gold folders
resource "azurerm_storage_account" "adls" {
  name                     = "adls${replace(lower(var.naming_suffix), "-", "")}"
  resource_group_name      = var.core_rg_name
  location                 = var.core_rg_location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
}

resource "azurerm_role_assignment" "adls_deployer_contributor" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "adls_adf_contributor" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.adf_identity_object_id
}

resource "azurerm_role_assignment" "adls_databricks_contributor" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.databricks_identity_object_id
}

# optional firewall rule when running in local_mode
resource "azurerm_storage_account_network_rules" "adls" {
  storage_account_id = azurerm_storage_account.adls.id
  default_action     = "Deny"
  ip_rules           = var.tf_in_automation == true ? [] : [var.deployer_ip_address]
}

# create filesystem for each zone
resource "azurerm_storage_data_lake_gen2_filesystem" "adls_zone" {
  for_each           = { for zone in var.zones : zone.name => zone }
  name               = lower(each.value.name)
  storage_account_id = azurerm_storage_account.adls.id

  depends_on = [
    azurerm_storage_account_network_rules.adls,
    azurerm_role_assignment.adls_deployer_contributor
  ]
}

# Create containers in filesystem
resource "azurerm_storage_data_lake_gen2_path" "adls_container" {
  for_each           = { for container in local.containers : "${container.zone}-${container.name}" => container }
  path               = lower(each.value.name)
  filesystem_name    = lower(each.value.zone)
  storage_account_id = azurerm_storage_account.adls.id
  resource           = "directory"

  depends_on = [
    azurerm_storage_account_network_rules.adls,
    azurerm_role_assignment.adls_deployer_contributor,
    azurerm_storage_data_lake_gen2_filesystem.adls_zone
  ]
}




# Private DNS and endpoint for ADLS Gen2
resource "azurerm_private_dns_zone" "adls" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = var.core_rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "adls" {
  name                  = "vnl-adls-${var.naming_suffix}"
  resource_group_name   = var.core_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.adls.name
  virtual_network_id    = data.azurerm_virtual_network.core.id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "adls" {
  name                = "adls-datalake-${lower(var.naming_suffix)}"
  location            = var.core_rg_location
  resource_group_name = var.core_rg_name
  subnet_id           = var.core_subnet_id

  private_service_connection {
    name                           = "adls-datalake-${lower(var.naming_suffix)}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.adls.id
    subresource_names              = ["dfs"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-group-adls-${var.naming_suffix}"
    private_dns_zone_ids = [azurerm_private_dns_zone.adls.id]
  }
}