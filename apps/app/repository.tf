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

resource "github_repository" "app" {
  count       = local.create_repo ? 1 : 0
  name        = var.app_id
  description = var.app_config.description
  visibility  = var.app_config.managed_repo.private ? "private" : "public"

  template {
    owner      = split("/", var.app_config.managed_repo.template)[0]
    repository = split("/", var.app_config.managed_repo.template)[1]
  }
}

resource "github_team" "owners" {
  count       = local.create_repo ? 1 : 0
  name        = "${var.app_id} - owners"
  description = "Owners of the ${var.app_id} FlowEHR app with push and PR/deployment approval permissions."
  privacy     = "closed"
}

resource "github_team_members" "owners" {
  for_each = local.create_repo ? var.app_config.managed_repo.owners : toset([])
  team_id  = github_team.owners[0].id

  members {
    username = each.value
    role     = "maintainer"
  }
}

resource "github_team_repository" "owners_repo_permissions" {
  count      = local.create_repo ? 1 : 0
  team_id    = github_team.owners[0].id
  repository = local.repository_name
  permission = "push"
}

resource "github_repository_file" "codeowners" {
  count               = local.create_repo ? 1 : 0
  repository          = local.repository_name
  branch              = "main"
  file                = "CODEOWNERS"
  content             = <<EOF
# Owners for branch protection
# Users within this team are required reviewers for this deployment branch
*       @${var.github_owner}/${github_team.owners[0].slug}
EOF
  commit_message      = "Add codeowners (managed by Terraform)"
  commit_author       = "Terraform"
  commit_email        = "terraform@flowehr.io"
  overwrite_on_create = true

  depends_on = [
    github_repository.app
  ]
}

resource "github_team" "contributors" {
  count       = local.create_repo ? 1 : 0
  name        = "${var.app_id} - contributors"
  description = "Contributors to the ${var.app_id} FlowEHR app with push permissions."
  privacy     = "closed"
}

resource "github_team_members" "contributors" {
  for_each = local.create_repo ? var.app_config.managed_repo.contributors : toset([])
  team_id  = github_team.contributors[0].id

  members {
    username = each.value
    role     = "member"
  }
}

resource "github_team_repository" "contributors_repo_permissions" {
  count      = local.create_repo ? 1 : 0
  team_id    = github_team.contributors[0].id
  repository = local.repository_name
  permission = "push"
}

resource "github_branch" "all" {
  for_each   = local.branches_and_envs
  repository = local.repository_name
  branch     = each.key

  depends_on = [
    # Need the codeowners file on each branch
    github_repository_file.codeowners
  ]
}

resource "github_branch_protection" "deployment" {
  for_each            = local.branches_and_envs
  repository_id       = local.repository_name
  pattern             = each.value
  allows_deletions    = false
  allows_force_pushes = false

  required_status_checks {
    strict   = var.accesses_real_data
    contexts = ["Lint"]
  }

  required_pull_request_reviews {
    dismiss_stale_reviews           = var.accesses_real_data
    restrict_dismissals             = var.accesses_real_data
    require_code_owner_reviews      = var.accesses_real_data
    required_approving_review_count = max(var.app_config.branch.num_of_approvals, 1)
  }
}

resource "azurerm_container_registry_scope_map" "app_access" {
  name                    = "acr-scopes-${replace(var.app_id, "_", "")}"
  container_registry_name = data.azurerm_container_registry.serve.name
  resource_group_name     = var.resource_group_name

  actions = [
    "repositories/${var.app_id}/content/read",
    "repositories/${var.app_id}/content/write"
  ]
}

resource "azurerm_container_registry_token" "app_access" {
  name                    = replace(replace(var.app_id, "_", ""), "-", "")
  container_registry_name = data.azurerm_container_registry.serve.name
  resource_group_name     = var.resource_group_name
  scope_map_id            = azurerm_container_registry_scope_map.app_access.id
}

resource "azurerm_container_registry_token_password" "app_access" {
  container_registry_token_id = azurerm_container_registry_token.app_access.id
  password1 {}
}

resource "github_repository_environment" "all" {
  for_each    = local.branches_and_envs
  repository  = local.repository_name
  environment = each.value

  deployment_branch_policy {
    custom_branch_policies = true
    protected_branches     = false
  }

  # TODO: remove when https://github.com/integrations/terraform-provider-github/pull/1530 is merged
  provisioner "local-exec" {
    command = <<EOF
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/${var.github_owner}/${local.repository_name}/environments/${each.value}/deployment-branch-policies \
  -f name='${each.key}'
EOF
  }

  depends_on = [
    github_repository.app
  ]
}

resource "github_actions_environment_secret" "acr_name" {
  for_each        = local.branches_and_envs
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ACR_NAME"
  plaintext_value = data.azurerm_container_registry.serve.name

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "acr_token_username" {
  for_each        = local.branches_and_envs
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ACR_USERNAME"
  plaintext_value = azurerm_container_registry_token.app_access.name

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "acr_token_password" {
  for_each        = local.branches_and_envs
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ACR_PASSWORD"
  plaintext_value = azurerm_container_registry_token_password.app_access.password1[0].value

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "acr_image_name" {
  for_each        = local.branches_and_envs
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "IMAGE_NAME"
  plaintext_value = local.acr_repository

  depends_on = [
    github_repository_environment.all
  ]
}

# If there is a staging environment defined then the SP is needed to bump the deployed
# docker version tag and in the production slot to slot swap
resource "github_actions_environment_secret" "sp_client_id" {
  for_each        = local.staging_gh_env != null ? local.branches_and_envs : {}
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ARM_CLIENT_ID"
  plaintext_value = azuread_application.webapp_sp[0].application_id

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "sp_client_secret" {
  for_each        = local.staging_gh_env != null ? local.branches_and_envs : {}
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ARM_CLIENT_SECRET"
  plaintext_value = azuread_application_password.webapp_sp[0].value

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "tenant_id" {
  for_each        = local.staging_gh_env != null ? local.branches_and_envs : {}
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ARM_TENANT_ID"
  plaintext_value = data.azurerm_client_config.current.tenant_id

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "subscription_id" {
  for_each        = local.staging_gh_env != null ? local.branches_and_envs : {}
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "ARM_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "webapp_id" {
  for_each        = local.staging_gh_env != null ? local.branches_and_envs : {}
  repository      = local.repository_name
  environment     = each.value
  secret_name     = "WEBAPP_ID"
  plaintext_value = azurerm_linux_web_app.app.id

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_actions_environment_secret" "slot_name" {
  count           = local.staging_gh_env != null ? 1 : 0
  repository      = local.repository_name
  environment     = local.staging_gh_env
  secret_name     = "SLOT_NAME"
  plaintext_value = local.staging_slot_name

  depends_on = [
    github_repository_environment.all
  ]
}

resource "github_repository_file" "deploy_workflows" {
  for_each            = local.envs_and_workflow_templates
  repository          = local.repository_name
  branch              = "main"
  file                = ".github/workflows/deploy_${each.key}.yml"
  content             = each.value.rendered
  commit_message      = "Add workflow (managed by Terraform)"
  commit_author       = "Terraform"
  commit_email        = "terraform@flowehr.io"
  overwrite_on_create = true

  depends_on = [
    # Only create these on main otherwise they will be triggered on push
    github_branch.all
  ]
}
