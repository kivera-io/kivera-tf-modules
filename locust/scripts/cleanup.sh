#!/bin/bash
set -e

base_dir=$(dirname "$0")/..

terraform -chdir="${base_dir}" destroy -auto-approve -var-file="${TFVARS_FILE}"
