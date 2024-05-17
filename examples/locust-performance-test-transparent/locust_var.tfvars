# Locust variables
nodes_instance_type       = "c5d.2xlarge"
nodes_count               = 45
locust_max_users          = 10000
locust_spawn_rate         = 50
locust_run_time           = "10m"
user_wait_min             = 4
user_wait_max             = 6
proxy_transparent_enabled = true

# AWS environment config
s3_bucket                          = "kivera-poc-deployment"
ec2_key_pair                       = "kivera-poc-keypair"
leader_username                    = "user"
leader_associate_public_ip_address = true
proxy_public_cert                  = <<-EOT
-----BEGIN CERTIFICATE-----
<<insert certificate contents here>>
-----END CERTIFICATE-----
EOT
