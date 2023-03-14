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

variable "naming_suffix" {
  type        = string
  description = "Suffix used to name resources"
}

variable "truncated_naming_suffix" {
  type        = string
  description = "Truncated (max 20 chars, no hyphens etc.) suffix for e.g storage accounts"
}

variable "environment" {
  type = string
}

variable "tags" {
  type = map(any)
}

variable "local_mode" {
  type = bool
}

variable "accesses_real_data" {
  type = bool
}

variable "core_rg_name" {
  type = string
}

variable "core_rg_location" {
  type = string
}

variable "core_log_analytics_name" {
  type = string
}

variable "core_kv_id" {
  type = string
}

variable "transform_feature_store_db_name" {
  type = string
}

variable "transform_feature_store_server_name" {
  type = string
}

variable "serve_app_service_plan_name" {
  type = string
}

variable "serve_cosmos_account_name" {
  type = string
}

variable "serve_acr_name" {
  type = string
}

variable "serve_webapps_subnet_id" {
  type = string
}

variable "github_owner" {
  type = string
}
