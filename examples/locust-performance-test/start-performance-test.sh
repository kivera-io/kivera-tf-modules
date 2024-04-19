#!/bin/bash
set -e

base_dir=$(pwd)
proxy_dir=$base_dir/proxy/aws-autoscaled-simple-scaling
locust_dir=$base_dir/performance-test/locust

proxy_var_file=$base_dir/examples/locust-performance-test/proxy_var.tfvars
locust_var_file=$base_dir/examples/locust-performance-test/locust_var.tfvars

terraform -chdir=$proxy_dir init -upgrade
[[ $CLEANUP != false ]] && trap "terraform -chdir=$proxy_dir destroy -var-file=$proxy_var_file --auto-approve" EXIT || echo "Skipping cleanup for proxy"
terraform -chdir=$proxy_dir apply -var-file=$proxy_var_file --auto-approve

export TF_VARS="-var-file=$locust_var_file -var=proxy_endpoint=$(terraform -chdir=$proxy_dir output --raw load_balancer_dns)"
$locust_dir/scripts/main.sh
