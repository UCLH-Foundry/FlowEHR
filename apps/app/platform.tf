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

resource "azurerm_application_insights" "app" {
  for_each                   = { for branch, env in local.branches_and_envs : env => branch }
  name                       = "ai-${replace(var.app_id, "_", "-")}-${each.key}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  workspace_id               = data.azurerm_log_analytics_workspace.core.id
  application_type           = "web"
  internet_ingestion_enabled = var.local_mode ? true : false
}

resource "azurerm_linux_web_app" "app" {
  name                      = "webapp-${replace(var.app_id, "_", "-")}-${var.naming_suffix}"
  resource_group_name       = var.resource_group_name
  location                  = var.location
  service_plan_id           = data.azurerm_service_plan.serve.id
  virtual_network_subnet_id = var.webapps_subnet_id
  https_only                = true

  site_config {
    container_registry_use_managed_identity = true
    remote_debugging_enabled                = var.local_mode

    # Only define the docker image to pull if there is not a staging slot
    dynamic "application_stack" {
      for_each = var.app_config.add_staging_slot ? {} : { "${local.acr_repository}" = var.app_id }

      content {
        docker_image     = "${var.acr_name}.azurecr.io/${var.app_id}"
        docker_image_tag = "latest"
      }
    }
  }

  app_settings = merge(var.app_config.env, {
    APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.app[local.core_gh_env].instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.app[local.core_gh_env].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    DOCKER_ENABLE_CI                           = var.app_config.add_staging_slot ? false : true
    COSMOS_STATE_STORE_ENDPOINT                = data.azurerm_cosmosdb_account.state_store.endpoint
    FEATURE_STORE_CONNECTION_STRING            = local.feature_store_odbc
    ENVIRONMENT                                = local.core_gh_env
  })

  identity {
    type = "SystemAssigned"
  }

  logs {
    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.app_config.add_staging_slot ? 1 : 0
  name           = local.staging_slot_name
  app_service_id = azurerm_linux_web_app.app.id
  https_only     = true

  site_config {
    container_registry_use_managed_identity = true
    remote_debugging_enabled                = var.local_mode

    # Application stack gets populated by GH actions
  }

  app_settings = merge(var.app_config.env, {
    APPINSIGHTS_INSTRUMENTATIONKEY             = azurerm_application_insights.app[local.staging_gh_env].instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.app[local.staging_gh_env].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    DOCKER_ENABLE_CI                           = true
    COSMOS_STATE_STORE_ENDPOINT                = data.azurerm_cosmosdb_account.state_store.endpoint
    FEATURE_STORE_CONNECTION_STRING            = local.feature_store_odbc
    ENVIRONMENT                                = local.staging_gh_env
  })

  identity {
    type = "SystemAssigned"
  }

  logs {
    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_role_assignment" "webapp_acr" {
  role_definition_name = "AcrPull"
  scope                = data.azurerm_container_registry.serve.id
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}

resource "azurerm_role_assignment" "webapp_staging_slot_acr" {
  count                = var.app_config.add_staging_slot ? 1 : 0
  role_definition_name = "AcrPull"
  scope                = data.azurerm_container_registry.serve.id
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

# Create a web hook that triggers automated deployment of the Docker image
resource "azurerm_container_registry_webhook" "webhook" {
  count               = var.app_config.add_staging_slot ? 0 : 1
  name                = "acrwh${replace(replace(var.app_id, "_", ""), "-", "")}"
  resource_group_name = var.resource_group_name
  location            = var.location
  registry_name       = data.azurerm_container_registry.serve.name

  service_uri = "https://${local.site_credential_name}:${local.site_credential_password}@${local.webapp_name_in_webhook}.scm.azurewebsites.net/api/registry/webhook"
  status      = "enabled"
  scope       = "${local.acr_repository}:latest"
  actions     = ["push"]

  custom_headers = {
    "Content-Type" = "application/json"
  }
}

resource "azurerm_cosmosdb_sql_database" "app" {
  name                = "${var.app_id}-state"
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_account_name
}

resource "azurerm_cosmosdb_sql_role_definition" "webapp" {
  name                = "${var.app_id}-AccessCosmosSingleDB"
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_account_name
  assignable_scopes   = ["${data.azurerm_cosmosdb_account.state_store.id}/dbs/${azurerm_cosmosdb_sql_database.app.name}"]

  permissions {
    data_actions = ["Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*"]
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "webapp" {
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_account_name
  role_definition_id  = azurerm_cosmosdb_sql_role_definition.webapp.id
  principal_id        = azurerm_linux_web_app.app.identity[0].principal_id
  scope               = "${data.azurerm_cosmosdb_account.state_store.id}/dbs/${azurerm_cosmosdb_sql_database.app.name}"
}

resource "azuread_application" "webapp_sp" {
  count        = local.staging_gh_env != null ? 1 : 0
  display_name = "sp-flowehr-app-${replace(var.app_id, "_", "-")}"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_application_password" "webapp_sp" {
  count                 = local.staging_gh_env != null ? 1 : 0
  application_object_id = azuread_application.webapp_sp[0].object_id
}

resource "azuread_service_principal" "webapp_sp" {
  count          = local.staging_gh_env != null ? 1 : 0
  application_id = azuread_application.webapp_sp[0].application_id
  owners         = [data.azurerm_client_config.current.object_id]
}

resource "azurerm_role_definition" "slot_swap" {
  count       = local.staging_gh_env != null ? 1 : 0
  name        = "role-slot-swap-on-${replace(var.app_id, "_", "-")}"
  scope       = azurerm_linux_web_app.app.id
  description = "Slot swap role"

  permissions {
    actions = [
      "Microsoft.Web/sites/config/read",
      "Microsoft.Web/sites/config/list/action",
      "Microsoft.Web/sites/config/read",
      "Microsoft.Web/sites/config/write",
      "Microsoft.Web/sites/slots/read",
      "Microsoft.Web/sites/slots/slotsswap/action",
      "Microsoft.Web/sites/slots/operationresults/read",
      "Microsoft.web/sites/slots/operations/read",
      "Microsoft.Web/sites/slots/config/list/action",
      "Microsoft.Web/sites/slots/config/read",
      "Microsoft.Web/sites/slots/config/write"
    ]
  }

  assignable_scopes = [
    azurerm_linux_web_app.app.id,
    azurerm_linux_web_app_slot.staging[0].id
  ]
}

resource "azurerm_role_assignment" "webapp_sp_slot_swap" {
  for_each = var.app_config.add_staging_slot ? {
    for idx, id in [azurerm_linux_web_app_slot.staging[0].id, azurerm_linux_web_app.app.id] : idx => id
  } : {}
  principal_id         = azuread_service_principal.webapp_sp[0].object_id
  scope                = each.value
  role_definition_name = azurerm_role_definition.slot_swap[0].name
}

// TODO: once Feature Store SQL SPN stuff is in, add connection from App Service here
