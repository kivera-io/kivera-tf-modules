# Locust variables
nodes_instance_type = "c5d.2xlarge"
nodes_count         = 45
locust_max_users    = 10000
locust_spawn_rate   = 50
locust_run_time     = "10m"
user_wait_min       = 4
user_wait_max       = 6

# AWS environment config
vpc_id                             = "vpc-id"
public_subnet_id                   = "subnet-id"
private_subnet_ids                 = ["subnet-id-1", "subnet-id-2", "subnet-id-3"]
s3_bucket                          = "s3-bucket"
ec2_key_pair                       = "kivera-poc-keypair"
leader_username                    = "user"
leader_associate_public_ip_address = true
