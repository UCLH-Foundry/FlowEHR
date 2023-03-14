#!/bin/bash
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
# limitations under the License.

set -o errexit
set -o pipefail
set -o nounset

# Export environment variables from a yaml config file ($1) and validate against a schema $2
export_config_from_yaml () {
  config_file_path=$1
  schema_file_path=$2

  if [ ! -f "$config_file_path" ]; then
    if [ -z "${TF_IN_AUTOMATION:-}" ]; then
        echo -e "\e[31m»»» 💥 Unable to find config file at path $config_file_path. Please create and try again.\e[0m"
        exit 1
    fi
  else
    # Validate no duplicate keys in config
    has_dupes=$(yq e '.. | select(. == "*") | {(path | .[-1]): .}| keys' "$config_file_path" | sort| uniq -d)
    if [ -n "${has_dupes:-}" ]; then
      echo -e "\e[31m»»» 💥 There are duplicate keys in your config, please fix and try again!\e[0m"
      exit 1
    fi

    # Validate config schema
    if [[ $(pajv validate -s "$schema_file_path" -d "$config_file_path") != *valid* ]]; then
      echo -e "\e[31m»»» ⚠️ Your config is invalid 😥 Please fix the errors and retry."
      exit 1
    fi

    # Get leaf keys yq query
    GET_LEAF_KEYS="del(.data_source_connections) | .. | select(. == \"*\") | {(path | .[-1]): .}"
    # Map keys to uppercase yq query
    UPCASE_KEYS="with_entries(.key |= upcase)"
    # Suffix keys with TF_VAR_ yq query
    TF_KEYS="with_entries(.key |= \"TF_VAR_\" + .)"
    # Yq query to format the output to be in form: key=value
    FORMAT_FOR_ENV_EXPORT="to_entries| map(.key + \"=\" +  .value)|join(\" \")"

    # Export as UPPERCASE keys env vars
    # shellcheck disable=SC2046
    export $(yq e "$GET_LEAF_KEYS|$UPCASE_KEYS| $FORMAT_FOR_ENV_EXPORT" "$config_file_path")

    # Export as Terraform keys env vars
    # shellcheck disable=SC2046
    export $(yq e "$GET_LEAF_KEYS|$TF_KEYS| $FORMAT_FOR_ENV_EXPORT" "$config_file_path")

    # Export the data source connections as json
    DATA_SOURCE_CONNECTIONS="$(yq -o=json eval '.data_source_connections' "$config_file_path")"
    if [ "$DATA_SOURCE_CONNECTIONS" == "null" ]; then
        DATA_SOURCE_CONNECTIONS='[]'
    fi
    export DATA_SOURCE_CONNECTIONS
fi
}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Export core config
echo "Loading core configuration..."
export_config_from_yaml "${SCRIPT_DIR}/../config.yaml" "${SCRIPT_DIR}/../config_schema.json"

# Export naming suffixes
NAMING_SUFFIX=$("${SCRIPT_DIR}/name_suffix.py")
echo "Naming resources with suffixed with: ${NAMING_SUFFIX}"
export NAMING_SUFFIX

TRUNCATED_NAMING_SUFFIX=$("${SCRIPT_DIR}/name_suffix.py" --truncated)
echo "Naming resources that have naming restrictions with: ${TRUNCATED_NAMING_SUFFIX}"
export TRUNCATED_NAMING_SUFFIX 

CORE_ADDRESS_SPACE=$(PYTHONHASHSEED=0 "${SCRIPT_DIR}/core_address_space.py")
echo "Using core address space: $CORE_ADDRESS_SPACE"
export CORE_ADDRESS_SPACE

# Export Terraform state vars
export MGMT_RG="rg-mgmt-${NAMING_SUFFIX}"
export MGMT_STORAGE="strgm${TRUNCATED_NAMING_SUFFIX}"
export STATE_CONTAINER="tfstate"

if [ "${TF_IN_AUTOMATION:-}" == "1" ]; then
    echo -e "Running terraform in automation setting LOCAL_MODE=false"
    export LOCAL_MODE="false"
fi

# Get IP address for local deployments
if [[ "${LOCAL_MODE}" == "true" ]];
then
    echo "Local Mode: TRUE"
    if [[ -z "${DEPLOYER_IP_ADDRESS+x}" ]];
    then
        echo "No IP address assigned in config, getting client IP and setting in ENV"
        this_ip="$(curl -s 'https://api64.ipify.org')"
        export DEPLOYER_IP_ADDRESS="${this_ip}"
    else
        echo "Have IP address from config.yaml"
    fi
    echo "IP Address: ${DEPLOYER_IP_ADDRESS}"
else
    echo "Local Mode: FALSE"
fi
