#!/bin/bash
set -e

base_dir=$(dirname "$0")/..

[[ -e ${TFVARS_FILE} ]] && TF_VARS="-var-file=${TFVARS_FILE} $TF_VARS" || (echo "No TFVARS_FILE found" && exit 1)
[[ -n ${PROXY_ENDPOINT} ]] && TF_VARS="$TF_VARS -var=proxy_endpoint=${PROXY_ENDPOINT}" || (echo "No PROXY_ENDPOINT found in env" && exit 1)

echo "locust tf_vars: $TF_VARS"
terraform -chdir="${base_dir}" init -upgrade
terraform -chdir="${base_dir}" apply $TF_VARS --auto-approve

deployment_id=$(terraform -chdir=${base_dir} output --raw deployment_id)
leader_address=$(terraform -chdir=${base_dir} output --raw leader_public_dns)
leader_username=$(terraform -chdir=${base_dir} output --raw leader_username)
leader_password=$(terraform -chdir=${base_dir} output --raw leader_password)
node_instance_name=$(terraform -chdir=${base_dir} output --raw node_instance_name)
leader_instance_name=$(terraform -chdir=${base_dir} output --raw leader_instance_name)
s3_bucket=$(terraform -chdir=${base_dir} output --raw s3_bucket)

deployed_time=$(date +"%Y-%m-%dT%T.%3N%z")
locust_run_time=$(terraform -chdir=${base_dir} output --raw locust_run_time)

results_dir="${base_dir}/temp/results/${deployment_id}"
mkdir -p "$results_dir/stats"

export DEPLOYMENT_ID=$deployment_id
export LEADER_ADDRESS=$leader_address
export LEADER_USERNAME=$leader_username
export LEADER_PASSWORD=$leader_password
export DEPLOYED_TIME=$deployed_time
export LOCUST_RUN_TIME=$locust_run_time
export NODE_INSTANCE_NAME=$node_instance_name
export LEADER_INSTANCE_NAME=$leader_instance_name
export RESULTS_DIR=$results_dir
export S3_BUCKET=$s3_bucket

if [[ $GITHUB_ACTIONS == true ]]; then
    echo "DEPLOYMENT_ID=$deployment_id" >> $GITHUB_ENV
    echo "LEADER_ADDRESS=$leader_address" >> $GITHUB_ENV
    echo "LEADER_USERNAME=$leader_username" >> $GITHUB_ENV
    echo "LEADER_PASSWORD=$leader_password" >> $GITHUB_ENV
    echo "DEPLOYED_TIME=$deployed_time" >> $GITHUB_ENV
    echo "LOCUST_RUN_TIME=$locust_run_time" >> $GITHUB_ENV
    echo "NODE_INSTANCE_NAME=$node_instance_name" >> $GITHUB_ENV
    echo "LEADER_INSTANCE_NAME=$leader_instance_name" >> $GITHUB_ENV
    echo "RESULTS_DIR=$results_dir" >> $GITHUB_ENV
    echo "S3_BUCKET=$s3_bucket" >> $GITHUB_ENV
fi
