#!/bin/bash
script_dir=$(dirname "$0")
set -e

function cleanup() {
    [[ $CLEANUP == "false" ]] && echo "Skipping cleanup" && exit 0
    ${script_dir}/cleanup.sh
    echo -e "\nResults in ${RESULTS_DIR}/"
}
trap cleanup EXIT

source ${script_dir}/deploy.sh
${script_dir}/get-results.sh
