output "vpc_cidr" {
  description = "VPC CIDR"
  value       = var.vpc_cidr
}

output "vpc_id" {
  description = "VPC ID"
    value       = aws_vpc.vpc.id
}

output "egress_subnet_id" {
  description = "VPC Public Subnet ID"
  value       = aws_subnet.public_subnet.id
}

output "inspection_subnet_id" {
  description = "VPC Proxy Subnet ID"
  value       = aws_subnet.proxy_subnet.id
}

output "private_subnet_id" {
  description = "VPC Private Subnet ID"
  value       = aws_subnet.private_subnet.id
}
