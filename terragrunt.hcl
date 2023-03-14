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

terraform {
  extra_arguments "auto_approve" {
    commands  = ["apply"]
    arguments = ["-auto-approve"]
  }
}

locals {
  terraform_version = "1.3.7"
  azure_provider = <<EOF
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      # Don't purge on destroy (this would fail due to purge protection being enabled on keyvault)
      purge_soft_delete_on_destroy               = false
      purge_soft_deleted_secrets_on_destroy      = false
      purge_soft_deleted_certificates_on_destroy = false
      purge_soft_deleted_keys_on_destroy         = false
      # When recreating an environment, recover any previously soft deleted secrets - set to true by default
      recover_soft_deleted_key_vaults   = true
      recover_soft_deleted_secrets      = true
      recover_soft_deleted_certificates = true
      recover_soft_deleted_keys         = true
    }
  }
}
EOF

  required_provider_azure = <<EOF
azurerm = {
  source  = "hashicorp/azurerm"
  version = ">= 3.32"
}
EOF

  required_provider_azuread = <<EOF
azuread = {
  source  = "hashicorp/azuread"
  version = "2.35.0"
}
EOF

  required_provider_random = <<EOF
random = {
  source = "hashicorp/random"
  version = "3.4.3"
}  
EOF

  required_provider_databricks = <<EOF
 databricks = {
    source = "databricks/databricks"
    version = "1.9.1"
  }
EOF

  required_provider_external = <<EOF
  external = {
    source = "hashicorp/external"
    version = "2.2.3"
  }
EOF

  required_provider_null = <<EOF
    null = {
      source = "hashicorp/null"
      version = "3.2.1"
    }
EOF

  required_provider_github = <<EOF
  github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
EOF
}

generate "terraform" {
  path      = "terraform.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = "${local.terraform_version}"

  required_providers {
    ${local.required_provider_azure}
    ${local.required_provider_null}
    ${local.required_provider_external}
  }
}
EOF
}

remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = get_env("MGMT_RG")
    storage_account_name = get_env("MGMT_STORAGE")
    container_name       = get_env("STATE_CONTAINER")
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.azure_provider
}

# Here we define common variables to be inhereted by each module (as long as they're set in its variables.tf)
inputs = {
  location = get_env("LOCATION")
  naming_suffix = get_env("NAMING_SUFFIX")
  truncated_naming_suffix = get_env("TRUNCATED_NAMING_SUFFIX")
  environment = get_env("ENVIRONMENT")
  deployer_ip_address = get_env("DEPLOYER_IP_ADDRESS", "") # deployer's IP address is added to resource firewall exceptions IF in local_mode
  local_mode = get_env("LOCAL_MODE", false)
  accesses_real_data = get_env("ACCESSES_REAL_DATA")
  core_address_space = get_env("CORE_ADDRESS_SPACE")
  tags = {
    environment = get_env("ENVIRONMENT")
  }
}
