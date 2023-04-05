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

resource "azurerm_resource_group" "core" {
  name     = "rg-${local.naming_suffix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "core" {
  name                          = "strg${local.naming_suffix_truncated}"
  resource_group_name           = azurerm_resource_group.core.name
  location                      = azurerm_resource_group.core.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  public_network_access_enabled = !var.tf_in_automation
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = var.tf_in_automation ? null : [data.http.local_ip[0].response_body]
  }
}

resource "azurerm_key_vault" "core" {
  name                       = "kv-${local.naming_suffix_truncated}"
  location                   = azurerm_resource_group.core.location
  resource_group_name        = azurerm_resource_group.core.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days = 7
  purge_protection_enabled   = var.accesses_real_data
  enable_rbac_authorization  = true
  sku_name                   = "standard"
  tags                       = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = var.tf_in_automation ? null : [data.http.local_ip[0].response_body]

    # Add CI subnets if any so deployer can access KV in automation
    virtual_network_subnet_ids = ([for subnet in data.azurerm_subnet.ci : subnet.id])
  }
}

resource "azurerm_role_assignment" "deployer_can_administrate_kv" {
  scope                = azurerm_key_vault.core.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_log_analytics_workspace" "core" {
  name                       = "log-${local.naming_suffix}"
  location                   = azurerm_resource_group.core.location
  resource_group_name        = azurerm_resource_group.core.name
  internet_ingestion_enabled = var.tf_in_automation ? false : true
  sku                        = "PerGB2018"
  retention_in_days          = 30
  tags                       = var.tags
}

resource "azurerm_monitor_action_group" "p0" {
  name                = "log-critical-action-group-${local.naming_suffix}"
  resource_group_name = azurerm_resource_group.core.name
  short_name          = "p0action"

  dynamic "email_receiver" {
    for_each = toset(var.alert_recipients)
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email
      use_common_alert_schema = true
    }
  }

  lifecycle {
    precondition {
      condition     = !var.accesses_real_data || length(var.alert_recipients) > 0
      error_message = "If this deployment accesses real data then there must be at least one recipient of alerts"
    }
  }
}

resource "azurerm_monitor_activity_log_alert" "keyvault" {
  name                = "activity-log-alert-kv-${local.naming_suffix}"
  resource_group_name = azurerm_resource_group.core.name
  scopes              = [azurerm_resource_group.core.id]
  description         = "Monitor security updates to the keyvault"

  criteria {
    resource_id    = azurerm_key_vault.core.id
    operation_name = "Microsoft.KeyVault/vaults/write"
    # This level is required to get updates when IP exceptions are added
    category = "Administrative"
    level    = "Informational"
  }

  action {
    action_group_id = azurerm_monitor_action_group.p0.id
  }
}
