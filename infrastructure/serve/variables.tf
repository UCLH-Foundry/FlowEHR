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
  type = string
}

variable "naming_suffix_truncated" {
  type = string
}

variable "tags" {
  type = map(any)
}

variable "core_rg_name" {
  type = string
}

variable "core_rg_location" {
  type = string
}

variable "core_subnet_id" {
  type = string
}

variable "accesses_real_data" {
  type    = bool
  default = false
}

variable "private_dns_zones" {
  type = map(any)
}

variable "algorithm_stewards_ad_group_principal_id" {
  type = string
}

variable "apps_ad_group_principal_id" {
  type = string
}
