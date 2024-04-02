
# Kivera Performance Testing Environment

Kivera uses [Locust](https://locust.io/) for performance testing. This repo includes all the neccessary files to perform the same performance test conducted by the team.

### Getting Started

1. Ensure all appropriate variables are included in the relevant var files. Refer to the relevant modules for more info on all available variables. Locust module in `/locust` and proxy module in `/proxy/aws-autoscaled-simple-scaling`
- `locust_var.tfvars`
- `proxy_var.tfvars`

2. Run the following script
```
./start-performance-test.sh
```