
# Kivera Performance Testing Environment

Kivera uses [Locust](https://locust.io/) for performance testing. This repo includes all the neccessary files to perform the same performance test conducted by the team.

### Getting Started

Ensure all appropriate variables are included in the relevant var files. Refer to the table below for all the required variables, and the modules for more info on all available variables. Locust module in `/locust` and proxy module in `/proxy/aws-autoscaled-simple-scaling`
| Module | Required TF Vars | Description |
|--|--|--|
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

### Deploy and run Locust performance test

Run the following script
```
./start-performance-test.sh
```