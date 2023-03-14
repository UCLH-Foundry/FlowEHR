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

output "feature_store_server_name" {
  value = azurerm_mssql_server.sql_server_features.name
}

output "feature_store_db_name" {
  value = azurerm_mssql_database.feature_database.name
}

output "adf_name" {
  value = azurerm_data_factory.adf.name
}
