
output "deployment_id" {
  value       = local.deployment_id
  description = "The id of the deployment. Suffixed to resource names"
}

output "leader_instance_name" {
  value       = local.locust_leader_instance_name
  description = "The ID of the leader instance."
}

output "node_instance_name" {
  value       = local.locust_node_instance_name
  description = "The ID of the proxy instance."
}

output "leader_instance_id" {
  value       = aws_instance.leader.id
  description = "The ID of the leader instance."
}

output "leader_public_ip" {
  value       = aws_instance.leader.public_ip
  description = "The public IP address of the leader instance."
}

output "leader_public_dns" {
  value       = aws_instance.leader.public_dns
  description = "The public DN address of the leader instance."
}

output "leader_private_ip" {
  value       = aws_instance.leader.private_ip
  description = "The private IP address of the leader instance."
}

output "nodes_public_ip" {
  value       = aws_instance.nodes.*.public_ip
  description = "The public IP address of the nodes instances."
}

output "nodes_private_ip" {
  value       = aws_instance.nodes.*.private_ip
  description = "The private IP address of the nodes instances."
}

output "leader_username" {
  value       = var.leader_username
  description = "The username for web access to the leader instance."
}

output "leader_password" {
  value       = random_string.leader_password.result
  description = "The password for web access to the leader instance."
}

output "locust_run_time" {
  value       = var.locust_run_time
  description = "The locust test run time in minutes."
}

output "s3_bucket" {
  value       = var.s3_bucket
  description = "The deployment bucket used in the deployment."
}
