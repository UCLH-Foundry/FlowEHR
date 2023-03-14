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
  repository_name = var.app_id

  feature_store_odbc = "Driver={ODBC Driver 18 for SQL Server};Server=tcp:${data.azurerm_mssql_server.feature_store.fully_qualified_domain_name},1433;Database=${var.feature_store_db_name};Authentication=ActiveDirectoryMsi;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
  acr_repository     = var.app_id
  create_repo        = var.app_config.managed_repo != null

  staging_slot_name   = "staging"
  core_gh_env         = var.environment
  core_branch_name    = local.core_gh_env
  staging_gh_env      = var.app_config.add_staging_slot ? "${var.environment}-testing_slot" : null
  staging_branch_name = local.staging_gh_env
  branches_and_envs = var.app_config.add_staging_slot ? {
    "${local.core_branch_name}"    = local.core_gh_env
    "${local.staging_branch_name}" = local.staging_gh_env
  } : { "${local.core_branch_name}" = local.core_gh_env }

  acr_deploy_reusable_workflow_filename = "acr_deploy_reusable.yml"
  slot_swap_reusable_workflow_filename  = "slot_swap_reusable.yml"

  envs_and_workflow_templates = var.app_config.add_staging_slot ? {
    "${local.core_gh_env}"    = data.template_file.core_github_workflow
    "${local.staging_gh_env}" = data.template_file.staging_github_workflow[0]
  } : { "${local.core_gh_env}" = data.template_file.core_github_workflow }

  webapp_name_in_webhook   = var.app_config.add_staging_slot ? "${lower(azurerm_linux_web_app.app.name)}-staging" : lower(azurerm_linux_web_app.app.name)
  site_credential_name     = var.app_config.add_staging_slot ? azurerm_linux_web_app_slot.staging[0].site_credential[0].name : azurerm_linux_web_app.app.site_credential[0].name
  site_credential_password = var.app_config.add_staging_slot ? azurerm_linux_web_app_slot.staging[0].site_credential[0].password : azurerm_linux_web_app.app.site_credential[0].password
}
