# Network 1
name_prefix                  = "kivera"
proxy_instance_type          = "c5d.xlarge"
ec2_key_pair                 = "kivera-poc-keypair"
load_balancer_cross_zone     = true
proxy_min_asg_size           = 6
proxy_max_asg_size           = 15
cache_enabled                = true
s3_bucket                    = "kivera-poc-deployment"
proxy_credentials_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:111111111111:secret:kivera-perf-test-credentials"
proxy_private_key_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:111111111111:secret:kivera-perf-test-private-key"
proxy_public_cert            = <<-EOT
-----BEGIN CERTIFICATE-----
<<insert certificate contents here>>
-----END CERTIFICATE-----
EOT
