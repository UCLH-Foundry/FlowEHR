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

module "app" {
  for_each                         = local.apps
  source                           = "./app"
  app_id                           = each.key
  naming_suffix                    = var.naming_suffix
  environment                      = var.environment
  local_mode                       = var.local_mode
  webapps_subnet_id                = var.serve_webapps_subnet_id
  resource_group_name              = var.core_rg_name
  location                         = var.core_rg_location
  log_analytics_name               = var.core_log_analytics_name
  app_service_plan_name            = var.serve_app_service_plan_name
  acr_name                         = var.serve_acr_name
  cosmos_account_name              = var.serve_cosmos_account_name
  feature_store_db_name            = var.transform_feature_store_db_name
  feature_store_server_name        = var.transform_feature_store_server_name
  apps_ad_group_display_name       = var.transform_apps_ad_group_display_name
  developers_ad_group_display_name = var.transform_developers_ad_group_display_name
  apps_ad_group_principal_id       = var.transform_apps_ad_group_principal_id
  developers_ad_group_principal_id = var.transform_developers_ad_group_principal_id
  github_owner                     = var.github_owner
  app_config                       = each.value
}
