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
# Uncomment this line to see each command for debugging (careful: this will show secrets!)
# set -o xtrace

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
FACTORY_NAME=$(cd "${SCRIPT_DIR}"/../infrastructure/transform && terragrunt output adf_name | tr -d '"')
RESOURCE_GROUP_NAME=$(cd "${SCRIPT_DIR}"/../infrastructure/core && terragrunt output core_rg_name | tr -d '"')
export FACTORY_NAME
export RESOURCE_GROUP_NAME

run_pipeline_and_wait () {
    local pipeline_name="${1}"
    echo "Run pipeline ${pipeline_name}"

    run_result=$(az datafactory pipeline create-run --factory-name "${FACTORY_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --name "${pipeline_name}")
    run_id=$(jq -r '.runId' <<< "${run_result}")

    echo "Wait for result"
    while true ; do 
        run_info=$(az datafactory pipeline-run show --factory-name "${FACTORY_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --run-id "${run_id}")
        run_status=$(jq -r '.status' <<< "${run_info}")

        if [[ "${run_status}" = "Succeeded" ]]; then 
            echo "Run ${run_id} of the pipeline ${pipeline_name} finished successfully"
            return
        fi

        if [[ ! "${run_status}" = "InProgress" && ! "${run_status}" = "Queued" ]]; then
            echo "Run ${run_id} of the pipeline ${pipeline_name} failed with status ${run_status} - please check the logs" 
            return 1
        fi
        sleep 5
    done 
}
export -f run_pipeline_and_wait

# shellcheck disable=SC2046
pipelines=$(jq -c -r '.[].name' <<< $(az datafactory pipeline list --factory-name "${FACTORY_NAME}" --resource-group "${RESOURCE_GROUP_NAME}"))
if ! echo "${pipelines}" | parallel run_pipeline_and_wait; then
    echo "One or more pipeline runs have failed - please check the logs"
    exit 1
fi
