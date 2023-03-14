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

locals {
  sql_server_features_admin_username = "adminuser"
  sql_owner_app_name                 = "flowehr-sql-owner-${lower(var.naming_suffix)}"
  databricks_app_name                = "flowehr-databricks-datawriter-${lower(var.naming_suffix)}"
  activities_file                    = "activities.json"
  artifacts_dir                      = "artifacts"
  adb_linked_service_name            = "ADBLinkedServiceViaMSI"

  all_activities_files = fileset(path.module, "../../transform/pipelines/**/${local.activities_file}")

  # Example value: [ "../../transform/pipelines/hello-world" ]
  pipeline_dirs = toset([
    for activity_file in local.all_activities_files : dirname(activity_file)
  ])

  # Example value: [ { "artifact_path" = "path/to/entrypoint.py", "pipeline" = "hello-world" } ]
  artifacts = flatten([
    for pipeline in local.pipeline_dirs : [
      for artifact in fileset("${pipeline}/${local.artifacts_dir}", "*") : {
        artifact_path = "${pipeline}/${local.artifacts_dir}/${artifact}"
        pipeline      = basename(pipeline)
      }
    ]
  ])
  storage_account_name = "dbfs${var.truncated_naming_suffix}"

  spark_version = yamldecode(file("../../config.transform.yaml")).spark_version

  data_source_connections_with_peerings = [
    for idx, item in var.data_source_connections : item if item.peering != null
  ]

  peerings = { for idx, item in local.data_source_connections_with_peerings :
    format("%s-%s", item.peering.virtual_network_name, item.peering.resource_group_name) => {
      virtual_network_name = item.peering.virtual_network_name
      resource_group_name  = item.peering.resource_group_name
    }
  }

  peered_vnet_ids = { for idx, item in data.azurerm_virtual_network.peered_data_source_networks :
    format("%s-%s", item.name, item.resource_group_name) => item.id
  }

  data_source_dns_zones = distinct(flatten([
    for idx, item in local.data_source_connections_with_peerings : [
      for idx, zone in item.peering.dns_zones : {
        name                = format("%s-%s", item.name, zone)
        dns_zone_name       = zone
        resource_group_name = item.peering.resource_group_name
      }
    ]
  ]))

  sql_users_to_create = {
    "users" : [
      { "name" : "${local.databricks_app_name}", "role" : "db_owner" },
      { "name" : "${azuread_group.ad_group_apps.display_name}", "role" : "db_reader" },
      { "name" : "${azuread_group.ad_group_developers.display_name}", "role" : "db_reader" },
      { "name" : "${azuread_group.ad_group_data_scientists.display_name}", "role" : "db_reader" },
    ]
  }
}
