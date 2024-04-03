#!/bin/bash
set -e

base_dir=$(dirname "$0")/..

terraform -chdir="${base_dir}" destroy $TF_VARS --auto-approve
