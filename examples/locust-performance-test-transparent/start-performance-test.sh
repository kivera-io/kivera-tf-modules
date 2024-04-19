#!/bin/bash
set -e

base_dir=$(pwd)
proxy_dir=$base_dir/examples/locust-performance-test-transparent/proxy
locust_dir=$base_dir/performance-test/locust
locust_var_file=$base_dir/examples/locust-performance-test-transparent/locust_var.tfvars

# Deploy infrastructure and transparent proxy
terraform -chdir=$proxy_dir init -upgrade
[[ $CLEANUP != false ]] && trap "terraform -chdir=$proxy_dir destroy --auto-approve" EXIT || echo "Skipping cleanup for proxy"
exit 0
terraform -chdir=$proxy_dir apply --auto-approve

tfvars="-var-file=$locust_var_file -var=proxy_endpoint=nil"
tfvars+=" -var=vpc_id=$(terraform -chdir=$proxy_dir output --raw vpc_id)"
tfvars+=" -var=public_subnet_id=$(terraform -chdir=$proxy_dir output --json public_subnet_ids | jq -r .[0])"
tfvars+=" -var=private_subnet_ids=$(terraform -chdir=$proxy_dir output --json private_subnet_ids)"
tfvars+=" -var=s3_bucket=$(terraform -chdir=$proxy_dir output --raw s3_bucket)"
export TF_VARS=$tfvars

# Poll ASG for health check
timeout=$((SECONDS + 600))
while true; do
    target_health=$(aws elbv2 describe-target-health --target-group-arn $(terraform -chdir=$proxy_dir output --raw target_group_arn))
    health_statuses=($(echo "$target_health" | jq -r '.TargetHealthDescriptions[].TargetHealth.State'))

    one_healthy=false
    for status in "${health_statuses[@]}"; do
        if [[ "$status" == "healthy" ]]; then
            one_healthy=true
            break
        fi
    done

    if [[ $one_healthy == true ]]; then
        echo "Proxy instance healthy..."
        sleep 30
        break
    elif [ $SECONDS -ge $timeout ]; then
        echo "Timeout reached. No healthy proxy instances. Exiting..."
        exit 1
    else
        echo -e "\e[1A\e[KWaiting for healthy proxy instance..."
        sleep 5
    fi
done

# Deploy and run Locust
$locust_dir/scripts/main.sh
