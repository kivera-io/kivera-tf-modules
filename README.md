# kivera-tf-modules

Repo containing a collection of Terraform modules used as an example for deploying Kivera and other relevant tools. The proxy can be used and deployed as a Terraform module.

```
.
├── examples                            # Examples of use case
│   └── locust-performance-test.sh      # Script for deploying and running Kivera proxy and Locust
├── performance-test                    #
│   └── Locust                          # Contains Locust performance test
│      ├── data                         # Contains user data for the Locust leader and node instances
│      ├── plans                        # Contains Python script containing AWS tests for Locust
│      └── script                       # Scripts for deploying and running Locust
├── proxy                               # Terraform modules for deploying Kivera proxy
│   └── aws-autoscaled-simple-scaling   # Deploys a simple proxy with auto scaling
└── README.md
```
