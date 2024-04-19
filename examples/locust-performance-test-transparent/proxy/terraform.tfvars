proxy_instance_type          = "c5d.xlarge"
proxy_min_asg_size           = 3
proxy_max_asg_size           = 12
cache_enabled                = true
ec2_key_pair                 = "key-pair"
s3_bucket                    = "s3-bucket"
proxy_credentials_secret_arn = "arn:aws:secretsmanager:arn"
proxy_private_key_secret_arn = "arn:aws:secretsmanager:arn"
proxy_public_cert            = <<-EOT
cert-here
EOT
