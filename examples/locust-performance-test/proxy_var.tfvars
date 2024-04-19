# Proxy variables
vpc_id                       = "vpc-id"
proxy_instance_type          = "c5d.xlarge"
key_pair_name                = "keypair-name"
load_balancer_subnet_ids     = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
cache_subnet_ids             = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
proxy_subnet_ids             = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
proxy_min_asg_size           = 1
proxy_max_asg_size           = 1
cache_enabled                = true
cache_type                   = "redis"
proxy_log_to_kivera          = true
proxy_log_to_cloudwatch      = true
s3_bucket                    = "s3-bucket"
proxy_credentials_secret_arn = "arn:aws:secretsmanager:arn"
proxy_private_key_secret_arn = "arn:aws:secretsmanager:arn"
proxy_public_cert            = <<-EOT
cert-here
EOT
