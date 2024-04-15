# output "vpc_service_endpoint_id" {
#   description = "VPC service endpoint id"
#   value       = aws_vpc_endpoint.glb_endpoint.id
# }

output "proxy_instance_id" {
  description = "Instance ID of proxy"
  value       = aws_launch_template.launch_template.id
}

output "target_group_arn" {
  description = "Proxy target group arn"
  value       = aws_lb_target_group.glb_target_group.arn
}
