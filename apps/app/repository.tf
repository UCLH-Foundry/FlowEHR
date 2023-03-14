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
  name        = var.app_id
  description = var.app_config.description
  visibility  = var.app_config.managed_repo.private ? "private" : "public"

  template {
    owner      = "UCLH-Foundry"
    repository = var.app_config.managed_repo.template
  }
}

resource "github_team" "owners" {
  name        = "${var.app_id} - owners"
  description = "Owners of the ${var.app_id} FlowEHR app with push and PR/deployment approval permissions."
  privacy     = "closed"
}

resource "github_team_members" "owners" {
  for_each = var.app_config.owners
  team_id  = github_team.owners.id

  members {
    username = each.key
    role     = "maintainer"
  }
}

resource "github_team_repository" "owners_repo_permissions" {
  team_id    = github_team.owners.id
  repository = github_repository.app.name
  permission = "push"
}

resource "github_repository_file" "codeowners" {
  repository          = github_repository.app.name
  branch              = var.environment
  file                = "CODEOWNERS"
  content             = <<EOF
# Owners for branch protection
# Users within this team are required reviewers for this deployment branch
*       @${var.github_owner}/${github_team.owners.slug}
EOF
  commit_message      = "Add codeowners (managed by Terraform)"
  commit_author       = "Terraform"
  commit_email        = "terraform@flowehr.io"
  overwrite_on_create = true
}

resource "github_team" "contributors" {
  name        = "${var.app_id} - contributors"
  description = "Contributors to the ${var.app_id} FlowEHR app with push permissions."
  privacy     = "closed"
}

resource "github_team_members" "contributors" {
  for_each = var.app_config.contributors
  team_id  = github_team.contributors.id

  members {
    username = each.key
    role     = "member"
  }
}

resource "github_team_repository" "contributors_repo_permissions" {
  team_id    = github_team.contributors.id
  repository = github_repository.app.name
  permission = "push"
}

resource "github_branch" "deployment" {
  repository = github_repository.app.name
  branch     = var.environment
}

resource "github_branch_protection" "deployment" {
  repository_id       = github_repository.app.name
  pattern             = var.environment
  allows_deletions    = false
  allows_force_pushes = false

  required_status_checks {
    strict   = true
    contexts = ["Lint"]
  }

  required_pull_request_reviews {
    dismiss_stale_reviews           = var.app_config.managed_repo.dismiss_stale_reviews
    restrict_dismissals             = true
    require_code_owner_reviews      = true
    required_approving_review_count = var.app_config.managed_repo.num_of_approvals
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

resource "github_repository_environment" "app" {
  repository  = github_repository.app.name
  environment = var.environment

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
  /repos/${var.github_owner}/${github_repository.app.name}/environments/${var.environment}/deployment-branch-policies \
  -f name='${var.environment}'
EOF
  }
}

resource "github_actions_environment_secret" "acr_name" {
  count           = local.is_prod ? 0 : 1
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ACR_NAME"
  plaintext_value = data.azurerm_container_registry.serve.name
}

resource "github_actions_environment_secret" "acr_token_username" {
  count           = local.is_prod ? 0 : 1
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ACR_USERNAME"
  plaintext_value = azurerm_container_registry_token.app_access.name
}

resource "github_actions_environment_secret" "acr_token_password" {
  count           = local.is_prod ? 0 : 1
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ACR_PASSWORD"
  plaintext_value = azurerm_container_registry_token_password.app_access.password1[0].value
}

resource "github_actions_environment_secret" "sp_client_id" {
  count           = local.is_prod ? 1 : 0
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ARM_CLIENT_ID"
  plaintext_value = azuread_application.webapp_sp[0].application_id
}

resource "github_actions_environment_secret" "sp_client_secret" {
  count           = local.is_prod ? 1 : 0
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ARM_CLIENT_SECRET"
  plaintext_value = azuread_application_password.webapp_sp[0].value
}

resource "github_actions_environment_secret" "tenant_id" {
  count           = local.is_prod ? 1 : 0
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ARM_TENANT_ID"
  plaintext_value = data.azurerm_client_config.current.tenant_id
}

resource "github_actions_environment_secret" "subscription_id" {
  count           = local.is_prod ? 1 : 0
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "ARM_SUBSCRIPTION_ID"
  plaintext_value = data.azurerm_client_config.current.subscription_id
}

resource "github_actions_environment_secret" "webapp_id" {
  count           = local.is_prod ? 1 : 0
  repository      = github_repository.app.name
  environment     = github_repository_environment.app.environment
  secret_name     = "WEBAPP_ID"
  plaintext_value = azurerm_linux_web_app.app.id
}
