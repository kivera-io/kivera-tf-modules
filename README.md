# kivera-tf-modules

Repo containing a collection of Terraform modules used as an example for deploying Kivera and other relevant tools. The proxy can be used and deployed as a Terraform module.

```
.
├── examples                                           # Examples of use case
|   ├── locust-performance-test                        # Example of performance testing explicit proxy
│   └── locust-performance-test-transparent            # Example of performance testing transparent proxy
├── network                                            # Terraform modules for custom networking environment
│   └── aws-network-transparent-proxy                  # Deploys the netowrking infrastructure for transparent proxy
├── performance-test                                   # Performance testing tools
│   └── locust                                         # Locust performance test
│      ├── data                                        # Contain user data scripts for the Locust leader and node instances
│      ├── plans                                       # Contains Python script with AWS tests for Locust
│      └── script                                      # Scripts for deploying and running Locust
├── proxy                                              # Terraform modules for deploying Kivera proxy
|   ├── aws-autoscaled-simple-scaling                  # Deploys a proxy in an autoscale group (implements dynamic scaling using "simple scaling")
│   └── aws-autoscaled-simple-scaling-transparent      # Deploys a transparent proxy in an autoscale group
└── README.md
```
