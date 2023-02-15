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


ROOT="/workspaces/FlowEHR"
PIPELINE_DIR="${ROOT}"/transform/pipelines
shopt -s globstar nullglob

# Walk through files in /transform/pipelines
# For each directory where activities.json has been found
for activity_json_file in "${PIPELINE_DIR}"/**/activities.json; do 
    pipeline_dir=$(dirname "${activity_json_file}")
    pushd "${pipeline_dir}"
    make artifacts
    popd
done