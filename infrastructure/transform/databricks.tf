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

resource "azurerm_databricks_workspace" "databricks" {
  name                                  = "dbks-${var.naming_suffix}"
  resource_group_name                   = var.core_rg_name
  managed_resource_group_name           = "rg-dbks-${var.naming_suffix}"
  location                              = var.core_rg_location
  sku                                   = "premium"
  infrastructure_encryption_enabled     = true
  public_network_access_enabled         = var.access_databricks_management_publicly
  network_security_group_rules_required = "NoAzureDatabricksRules"
  tags                                  = var.tags

  custom_parameters {
    no_public_ip                                         = true
    storage_account_name                                 = local.dbfs_storage_account_name
    public_subnet_name                                   = data.azurerm_subnet.databricks_host.name
    private_subnet_name                                  = data.azurerm_subnet.databricks_container.name
    virtual_network_id                                   = data.azurerm_virtual_network.core.id
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.databricks_host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.databricks_container.id
  }
}

# Allow Databricks network configuration to propagate
resource "time_sleep" "wait_for_databricks_network" {
  create_duration = "180s"

  depends_on = [
    azurerm_databricks_workspace.databricks,
    azurerm_private_endpoint.databricks_control_plane,
    azurerm_private_endpoint.databricks_filesystem,
    azurerm_subnet_route_table_association.databricks_host,
    azurerm_subnet_route_table_association.databricks_container,
    azurerm_subnet_route_table_association.shared
  ]
}

data "databricks_spark_version" "latest" {
  spark_version = var.transform.spark_version
  depends_on = [
    time_sleep.wait_for_databricks_network,
    azurerm_databricks_workspace.databricks
  ]
}

data "databricks_node_type" "smallest" {
  # Providing no required configuration, Databricks will pick the smallest node possible
  depends_on = [time_sleep.wait_for_databricks_network]
}

# for prod - this will select something like E16ads v5 => ~$1.18ph whilst running
data "databricks_node_type" "prod" {
  min_memory_gb       = 128
  min_cores           = 16
  local_disk_min_size = 600
  category            = "Memory Optimized"
}

resource "databricks_cluster" "fixed_single_node" {
  cluster_name            = "Fixed Job Cluster"
  spark_version           = data.databricks_spark_version.latest.id
  node_type_id            = var.accesses_real_data ? data.databricks_node_type.prod.id : data.databricks_node_type.smallest.id
  autotermination_minutes = 10

  spark_conf = merge(
    # Secrets for SQL Feature store
    # Formatted according to syntax for referencing secrets in Spark config:
    # https://learn.microsoft.com/en-us/azure/databricks/security/secrets/secrets
    tomap({
      "spark.secret.feature-store-app-id"     = "{{secrets/${databricks_secret_scope.secrets.name}/${databricks_secret.flowehr_databricks_sql_spn_app_id.key}}}"
      "spark.secret.feature-store-app-secret" = "{{secrets/${databricks_secret_scope.secrets.name}/${databricks_secret.flowehr_databricks_sql_spn_app_secret.key}}}"
      "spark.secret.feature-store-fqdn"       = "{{secrets/${databricks_secret_scope.secrets.name}/${databricks_secret.flowehr_databricks_sql_fqdn.key}}}"
      "spark.secret.feature-store-database"   = "{{secrets/${databricks_secret_scope.secrets.name}/${databricks_secret.flowehr_databricks_sql_database.key}}}"
    }),
    # MSI connection to Datalake (if enabled)
    var.transform.datalake != null ? tomap({
      "fs.azure.account.auth.type.${module.datalake[0].adls_name}.dfs.core.windows.net"              = "OAuth",
      "fs.azure.account.oauth.provider.type.${module.datalake[0].adls_name}.dfs.core.windows.net"    = "org.apache.hadoop.fs.azurebfs.oauth2.ClientCredsTokenProvider",
      "fs.azure.account.oauth2.client.id.${module.datalake[0].adls_name}.dfs.core.windows.net"       = module.datalake[0].databricks_adls_app_id,
      "fs.azure.account.oauth2.client.secret.${module.datalake[0].adls_name}.dfs.core.windows.net"   = "{{secrets/${databricks_secret_scope.secrets.name}/${module.datalake[0].databricks_adls_app_secret_key}}}",
      "fs.azure.account.oauth2.client.endpoint.${module.datalake[0].adls_name}.dfs.core.windows.net" = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}/oauth2/token"
      "spark.secret.datalake-uri"                                                                    = "{{secrets/${databricks_secret_scope.secrets.name}/${module.datalake[0].databricks_adls_uri_secret_key}}}"
    }) : tomap({}),
    # Secrets for each data source
    tomap({ for connection in var.data_source_connections :
      "spark.secret.${connection.name}-fqdn" => "{{secrets/${databricks_secret_scope.secrets.name}/flowehr-dbks-${connection.name}-fqdn}}"
    }),
    tomap({ for connection in var.data_source_connections :
      "spark.secret.${connection.name}-database" => "{{secrets/${databricks_secret_scope.secrets.name}/flowehr-dbks-${connection.name}-database}}"
    }),
    tomap({ for connection in var.data_source_connections :
      "spark.secret.${connection.name}-username" => "{{secrets/${databricks_secret_scope.secrets.name}/flowehr-dbks-${connection.name}-username}}"
    }),
    tomap({ for connection in var.data_source_connections :
      "spark.secret.${connection.name}-password" => "{{secrets/${databricks_secret_scope.secrets.name}/flowehr-dbks-${connection.name}-password}}"
    }),
    # Additional secrets from the config
    tomap({ for secret in var.transform.databricks_secrets :
      "spark.secret.${secret.key}" => "{{secrets/${databricks_secret_scope.secrets.name}/${secret.key}}}"
    }),
    # Any values set in the config
    tomap({ for config_value in var.transform.spark_config :
      config_value.key => config_value.value
    })
  )

  dynamic "library" {
    for_each = var.transform.databricks_libraries.pypi
    content {
      pypi {
        package = library.value.package
        repo    = library.value.repo
      }
    }
  }

  dynamic "library" {
    for_each = var.transform.databricks_libraries.maven
    content {
      maven {
        coordinates = library.value.coordinates
        repo        = library.value.repo
        exclusions  = library.value.exclusions
      }
    }
  }

  dynamic "library" {
    for_each = var.transform.databricks_libraries.cran
    content {
      cran {
        package = library.value.package
        repo    = library.value.repo
      }
    }
  }

  dynamic "library" {
    for_each = var.transform.databricks_libraries.whl
    content {
      whl = library.value
    }
  }

  dynamic "library" {
    for_each = var.transform.databricks_libraries.egg
    content {
      egg = library.value
    }
  }

  dynamic "library" {
    for_each = var.transform.databricks_libraries.jar
    content {
      jar = library.value
    }
  }

  dynamic "init_scripts" {
    for_each = var.transform.init_scripts
    content {
      dbfs {
        destination = "dbfs:/${local.init_scripts_dir}/${basename(init_scripts.value)}"
      }
    }
  }

  cluster_log_conf {
    dbfs {
      destination = "dbfs:/${local.cluster_logs_dir}"
    }
  }

  spark_env_vars = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.transform.connection_string
  }

  custom_tags = {
    "ResourceClass" = "SingleNode"
  }

  depends_on = [time_sleep.wait_for_databricks_network]
}

resource "databricks_dbfs_file" "dbfs_init_script_upload" {
  for_each = toset(var.transform.init_scripts)
  # Source path on local filesystem
  source = each.key
  # Path on DBFS
  path = "/${local.init_scripts_dir}/${basename(each.key)}"

  depends_on = [time_sleep.wait_for_databricks_network]
}

# databricks secret scope, in-built. Not able to use key vault backed scope due to limitation in databricks:
# https://learn.microsoft.com/en-us/azure/databricks/security/secrets/secret-scopes#--create-an-azure-key-vault-backed-secret-scope-using-the-databricks-cli 
resource "databricks_secret_scope" "secrets" {
  name       = "flowehr-secrets"
  depends_on = [time_sleep.wait_for_databricks_network]
}
