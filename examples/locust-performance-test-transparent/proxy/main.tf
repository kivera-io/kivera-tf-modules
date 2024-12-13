module "network" {
  source = "git::https://github.com/kivera-io/kivera-tf-modules.git//network/aws-network-transparent-proxy"
}

module "proxy" {
  source = "git::https://github.com/kivera-io/kivera-tf-modules.git//proxy/aws-autoscaled-simple-scaling-transparent"

  vpc_id                       = module.network.vpc_id
  proxy_subnet_ids             = module.network.inspection_subnet_ids
  private_subnet_ids           = module.network.private_subnet_ids
  cache_subnet_ids             = module.network.inspection_subnet_ids
  proxy_instance_type          = var.proxy_instance_type
  proxy_min_asg_size           = var.proxy_min_asg_size
  proxy_max_asg_size           = var.proxy_max_asg_size
  cache_enabled                = var.cache_enabled
  s3_bucket                    = var.s3_bucket
  ec2_key_pair                 = var.ec2_key_pair
  load_balancer_cross_zone     = var.load_balancer_cross_zone
  proxy_credentials_secret_arn = var.proxy_credentials_secret_arn
  proxy_private_key_secret_arn = var.proxy_private_key_secret_arn
  proxy_public_cert            = var.proxy_public_cert
}

module "network-changes" {
  source = "git::https://github.com/kivera-io/kivera-tf-modules.git//network/aws-network-transparent-proxy/route-table-updates"

  vpc_id               = module.network.vpc_id
  public_subnet_id     = element(module.network.egress_subnet_ids, 0)
  private_subnet_id    = element(module.network.private_subnet_ids, 0)
  vpc_endpoint_id      = module.proxy.vpc_service_endpoint_id
  private_subnet_rt_id = module.network.private_subnet_rt_id
  ec2_key_pair         = var.ec2_key_pair
  proxy_public_cert    = var.proxy_public_cert
}
