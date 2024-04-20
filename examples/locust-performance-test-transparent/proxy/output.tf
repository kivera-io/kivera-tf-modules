output "vpc_id" {
  description = "Created VPC id"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Created public subnet id"
  value       = module.network.egress_subnet_ids
}

output "private_subnet_ids" {
  description = "Created private subnet id"
  value       = module.network.private_subnet_ids
}

output "s3_bucket" {
  description = "S3 bucket used for deployment"
  value       = var.s3_bucket
}

output "target_group_arn" {
  description = "Proxy target group arn"
  value       = module.proxy.target_group_arn
}
