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

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

generate "terraform" {
  path      = "terraform.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = "${include.root.locals.terraform_version}"

  required_providers {
    ${include.root.locals.required_provider_azure}
    ${include.root.locals.required_provider_github}
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
${include.root.locals.azure_provider}

provider "github" {}
EOF
}

dependency "core" {
  config_path = "${get_repo_root()}/infrastructure/core"

  mock_outputs = {
    core_rg_name            = "core_rg_name"
    core_rg_location        = "core_rg_location"
    core_kv_id              = "core_kv_id"
    core_log_analytics_name = "core_log_analytics_name"
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

dependency "transform" {
  config_path = "${get_repo_root()}/infrastructure/transform"

  mock_outputs = {
    feature_store_server_name = "transform_feature_store_server_name"
    feature_store_db_name     = "transform_feature_store_db_name"
    apps_ad_group_display_name = "transform_apps_ad_group_display_name"
    developers_ad_group_display_name = "transform_developers_ad_group_display_name"
    apps_ad_group_principal_id = "transform_apps_ad_group_principal_id"
    developers_ad_group_principal_id = "transform_developers_ad_group_principal_id"
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

dependency "serve" {
  config_path = "${get_repo_root()}/infrastructure/serve"

  mock_outputs = {
    app_service_plan_name = "serve_app_service_plan_name"
    acr_name              = "serve_acr_name"
    cosmos_account_name   = "serve_cosmos_account_name"
    webapps_subnet_id     = "serve_webapps_subnet_id"
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

inputs = {
  core_rg_name            = dependency.core.outputs.core_rg_name
  core_rg_location        = dependency.core.outputs.core_rg_location
  core_kv_id              = dependency.core.outputs.core_kv_id
  core_log_analytics_name = dependency.core.outputs.core_log_analytics_name

  transform_feature_store_server_name  = dependency.transform.outputs.feature_store_server_name
  transform_feature_store_db_name      = dependency.transform.outputs.feature_store_db_name
  transform_apps_ad_group_display_name = dependency.transform.outputs.apps_ad_group_display_name
  transform_developers_ad_group_display_name = dependency.transform.outputs.developers_ad_group_display_name
  transform_apps_ad_group_principal_id = dependency.transform.outputs.apps_ad_group_principal_id
  transform_developers_ad_group_principal_id = dependency.transform.outputs.developers_ad_group_principal_id

  serve_app_service_plan_name = dependency.serve.outputs.app_service_plan_name
  serve_acr_name              = dependency.serve.outputs.acr_name
  serve_cosmos_account_name   = dependency.serve.outputs.cosmos_account_name
  serve_webapps_subnet_id     = dependency.serve.outputs.webapps_subnet_id


  github_owner = get_env("GITHUB_OWNER", "")
}
