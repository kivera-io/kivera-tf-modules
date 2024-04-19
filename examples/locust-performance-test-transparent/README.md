
# Kivera Performance Testing Environment

Kivera uses [Locust](https://locust.io/) for performance testing. This repo includes all the necessary files to perform the same performance test conducted by the team.

### Getting Started
Ensure all appropriate variables are included in the relevant var files (`proxy/terraform.tfvars` and `locust_var.tfvars`). Refer to the table below, and the modules for more info on all available variables. Locust module in `/locust` and proxy module in `/proxy/aws-autoscaled-simple-scaling-transparent`

Proxy setting `allow non cloud` is required to be enabled, along with `default allow`. This is to ensure the instances are able to install all required packages for the performance test.

### Deploy and run Locust performance test
Run the following script from the repository root folder:
```
./examples/locust-performance-test-transparent/start-performance-test.sh
```

### Note
The tests are defined in `performance-test/locust/plans/test.py` as a list of AWS calls. Some are expected to blocked by Kivera whilst others are expected to reach AWS. A custom IAM role is used by Locust which only has readonly permissions.

### Terraform Variables
In `proxy/terraform.tfvars` TF vars used to deploy and run the performance test are:
| TF Vars | Description | Required |
|---------|-------------|----------|
| `proxy_credentials` | Proxy credentials as json string | Yes |
| `proxy_credentials_secret_arn` | ARN of proxy credentials (if `proxy_credentials` not provided) | Yes |
| `proxy_private_key` | Private key/cert to be used by Kivera proxy | Yes |
| `proxy_private_key_secret_arn` | ARN of private key (if `proxy_private_key` not provided) | Yes |
| `proxy_public_cert` | Public key/cert associated with `proxy_private_key` | Yes |
| `s3_bucket` | Name of the bucket used to upload the tests/files | Yes |
| `key_pair_name` | Name of an existing EC2 KeyPair to enable SSH access to the instances | - |
| `proxy_instance_type` | Instance type to deploy the proxy into | - |
| `cache_enabled` | Enable to use redis alongside the proxy | - |
| `proxy_min_asg_size` | Minimum number of proxy instances | - |
| `proxy_max_asg_size` | Maximum number of proxy instances | - |

In `locust_var.tfvars` TF vars used to deploy and run the performance test are:
| TF Vars | Description | Required |
|---------|-------------|----------|
| `s3_bucket` | Name of the bucket used to upload the tests/files | Yes |
| `nodes_count` | Number of total nodes/instances | - |
| `locust_max_users` | Max number of Locust users | - |
| `locust_spawn_rate` | Rate at which Locust users spawn (per second) | - |
| `locust_run_time` | Duration of the Locust test (e.g. 20s, 3m, 2h, 1h23m45s) | - |
