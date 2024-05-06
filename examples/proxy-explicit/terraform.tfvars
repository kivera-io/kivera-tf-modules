proxy_instance_type          = "c5d.xlarge"
ec2_key_pair                 = "kivera-poc-keypair"
vpc_id                       = "vpc-id"
load_balancer_subnet_ids     = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
cache_subnet_ids             = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
proxy_subnet_ids             = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
proxy_min_asg_size           = 3
proxy_max_asg_size           = 12
cache_enabled                = false
s3_bucket                    = "kivera-poc-deployment"
proxy_credentials_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:111111111111:secret:kivera-perf-test-credentials"
proxy_private_key_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:111111111111:secret:kivera-perf-test-private-key"
proxy_public_cert            = <<-EOT
-----BEGIN CERTIFICATE-----
<<insert certificate contents here>>
-----END CERTIFICATE-----
EOT
