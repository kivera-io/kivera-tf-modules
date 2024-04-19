#!/bin/bash
set -e

base_dir=$(pwd)
proxy_dir=$base_dir/examples/locust-performance-test-transparent/proxy
locust_dir=$base_dir/performance-test/locust

locust_var_file=$base_dir/examples/locust-performance-test-transparent/locust_var.tfvars

terraform -chdir=$proxy_dir init -upgrade
[[ $CLEANUP != false ]] && ehco "Skipping cleanup for proxy" && trap "terraform -chdir=$proxy_dir destroy --auto-approve" EXIT
terraform -chdir=$proxy_dir apply --auto-approve

tfvars="-var-file=$locust_var_file"
tfvars+=" -var=vpc_id=$(terraform -chdir=$proxy_dir output --raw vpc_id)"
tfvars+=" -var=public_subnet_id=$(terraform -chdir=$proxy_dir output --json public_subnet_ids | jq -r .[0])"
tfvars+=" -var=private_subnet_ids=$(terraform -chdir=$proxy_dir output --json private_subnet_ids)"
tfvars+=" -var=s3_bucket=$(terraform -chdir=$proxy_dir output --raw s3_bucket)"

export TF_VARS=$tfvars
$locust_dir/scripts/main.sh
