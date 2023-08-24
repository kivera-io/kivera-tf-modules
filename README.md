# kivera-tf-modules

To use a module:

```
module "kivera" {
  source = "git::https://github.com/kivera-io/kivera-tf-modules.git//proxy/aws-autoscaled-simple-scaling"

  proxy_credentials           = var.proxy_credentials
  proxy_private_key           = var.proxy_private_key
  proxy_public_cert           = var.proxy_public_cert
  proxy_instance_type         = var.proxy_instance_type
  key_pair_name               = var.key_pair_name
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.subnet_ids
  load_balancer_internal      = var.load_balancer_internal
  proxy_allowed_ingress_range = var.proxy_allowed_ingress_range
  proxy_allowed_ssh_range     = var.proxy_allowed_ssh_range
}
```
