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

output "cosmos_account_name" {
  value = azurerm_cosmosdb_account.serve.name
}

output "app_service_plan_name" {
  value = azurerm_service_plan.serve.name
}

output "acr_name" {
  value = azurerm_container_registry.serve.name
}

output "serve_key_vault_uri" {
  value = azurerm_key_vault.serve.vault_uri
}

output "serve_key_vault_id" {
  value = azurerm_key_vault.serve.id
}
