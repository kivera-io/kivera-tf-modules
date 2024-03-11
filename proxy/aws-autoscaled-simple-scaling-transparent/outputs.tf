output "vpc_service_endpoint_id" {
  description = "VPC service endpoint id"
  value       = aws_vpc_endpoint.glb_endpoint.id
}

output "proxy_instance_id" {
  description = "Instance ID of proxy"
  value       = aws_launch_template.launch_template.id
}

output "auto_scaling_group_name" {
  description = "Auto scaling group name"
  value       = aws_autoscaling_group.auto_scaling_group.name
}
