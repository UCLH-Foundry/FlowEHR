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

# Private endpoint in the Core Resource group
# If the metastore is created as part of this deployment, the private endpoint will already be created
resource "azurerm_private_endpoint" "metastore_storage" {
  for_each = var.metastore_created ? {} : {
    "dfs"  = var.private_dns_zones["dfs"].id
    "blob" = var.private_dns_zones["blob"].id
  }

  name                = "pe-uc-${each.key}-${var.naming_suffix}"
  location            = data.azurerm_resource_group.core_rg.location
  resource_group_name = var.core_rg_name
  subnet_id           = data.azurerm_subnet.shared_subnet.id

  private_service_connection {
    name                           = "uc-${each.key}-${var.naming_suffix}"
    is_manual_connection           = false
    private_connection_resource_id = data.azurerm_storage_account.metastore_storage_account.id
    subresource_names              = [each.key]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-group-${each.key}-${var.naming_suffix}"
    private_dns_zone_ids = [each.value]
  }
}
