
# Kivera Performance Testing Environment

Kivera uses [Locust](https://locust.io/) for performance testing. This repo includes all the necessary files to perform the same performance test conducted by the team.

### Getting Started
Ensure all appropriate variables are included in the relevant var files (`locust_var.tfvars` and `proxy_var.tfvars`). Refer to the table below, and the modules for more info on all available variables. Locust module in `/locust` and proxy module in `/proxy/aws-autoscaled-simple-scaling`

### Deploy and run Locust performance test
Run the following script
```
./start-performance-test.sh
```

### Note
The tests are defined in `performance-test/locust/plans/test.py` as a list of AWS calls. Some are expected to blocked by Kivera whilst others are expected to reach AWS. A custom IAM role is used by Locust which only has readonly permissions.

### Terraform Variables
TF vars **required** to deploy and run the performance test:
| Module | Required TF Vars | Description |
|--------|------------------|-------------|
| Proxy | `proxy_credentials` | Proxy credentials as json string |
| Proxy | `proxy_credentials_secret_arn` | ARN of proxy credentials (if `proxy_credentials` not provided) |
| Proxy | `proxy_private_key` | Private key/cert to be used by Kivera proxy |
| Proxy | `proxy_private_key_secret_arn` | ARN of private key (if `proxy_private_key` not provided) |
| Proxy | `proxy_public_cert` | Public key/cert associated with `proxy_private_key` |
| Proxy | `key_pair_name` | Name of an existing EC2 KeyPair to enable SSH access to the instances |
| Proxy | `vpc_id` | VPC to deploy the proxy into |
| Proxy | `proxy_subnet_ids` | Subnets to deploy the proxy into |
| Proxy | `load_balancer_subnet_ids` | Subnets to deploy the load balancer into |
| Proxy | `s3_bucket` | Name of the bucket used to upload the tests/files |
| Locust | `vpc_id` | VPC to deploy the proxy into |
| Locust | `public_subnet_id` | Public subnet to deploy the Locust leader |
| Locust | `private_subnet_ids` | Private subnets to deploy the Locust nodes |
---
TF vars **recommended** to customize when deploying and running the performance test:
| Module | Recommended TF Vars | Description |
|--------|---------------------|-------------|
| Proxy | `proxy_min_asg_size` | Minimum number of proxy instances |
| Proxy | `proxy_max_asg_size` | Maximum number of proxy instances |
| Locust | `nodes_count` | Number of total nodes/instances |
| Locust | `public_subnet_id` | Public subnet to deploy the Locust leader |
| Locust | `private_subnet_ids` | Private subnets to deploy the Locust nodes |
| Locust | `locust_max_users` | Max number of Locust users |
| Locust | `locust_spawn_rate` | Rate at which Locust users spawn (per second) |
| Locust | `locust_run_time` | Duration of the Locust test (e.g. 20s, 3m, 2h, 3h30m10s) |