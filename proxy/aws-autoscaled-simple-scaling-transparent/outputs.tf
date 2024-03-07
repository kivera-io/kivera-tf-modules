output "vpc_service_endpoint_id" {
  description = "VPC Service Endpoint"
  value = aws_vpc_endpoint.glb_endpoint.id
}

output "proxy_instance_id" {
  description = "Instance ID of proxy"
  value       = aws_launch_template.launch_template.id
}
