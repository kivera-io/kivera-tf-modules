output "vpc_cidr" {
  description = "VPC CIDR"
  value       = var.vpc_cidr
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vpc.id
}

output "egress_subnet_ids" {
  description = "List of VPC Public Subnet IDs"
  value       = tolist([for i in aws_subnet.public_subnet : i.id])
}

output "inspection_subnet_ids" {
  description = "List of VPC Proxy Subnet IDs"
  value       = tolist([for i in aws_subnet.proxy_subnet : i.id])
}

output "private_subnet_ids" {
  description = "List of VPC Private Subnet IDs"
  value       = tolist([for i in aws_subnet.private_subnet : i.id])
}

output "private_subnet_rt_id" {
  description = "VPC Private Subnet Route Table ID"
  value       = aws_route_table.private_subnet_route_table.id
}
