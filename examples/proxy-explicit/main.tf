module "kivera-proxy" {
  source = "git::https://github.com/kivera-io/kivera-tf-modules.git//proxy/aws-autoscaled-simple-scaling"

  proxy_instance_type          = var.proxy_instance_type
  proxy_subnet_ids             = var.proxy_subnet_ids
  proxy_log_to_kivera          = var.proxy_log_to_kivera
  proxy_log_to_cloudwatch      = var.proxy_log_to_cloudwatch
  proxy_allowed_ingress_range  = var.proxy_allowed_ingress_range
  proxy_allowed_ssh_range      = var.proxy_allowed_ssh_range
  proxy_min_asg_size           = var.proxy_min_asg_size
  proxy_max_asg_size           = var.proxy_max_asg_size
  cache_subnet_ids             = var.cache_subnet_ids
  cache_enabled                = var.cache_enabled
  ec2_key_pair                 = var.ec2_key_pair
  vpc_id                       = var.vpc_id
  load_balancer_subnet_ids     = var.load_balancer_subnet_ids
  load_balancer_internal       = var.load_balancer_internal
  s3_bucket                    = var.s3_bucket
  s3_bucket_key                = var.s3_bucket_key
  proxy_credentials            = var.proxy_credentials
  proxy_private_key            = var.proxy_private_key
  proxy_credentials_secret_arn = var.proxy_credentials_secret_arn
  proxy_private_key_secret_arn = var.proxy_private_key_secret_arn
  proxy_public_cert            = var.proxy_public_cert
}
