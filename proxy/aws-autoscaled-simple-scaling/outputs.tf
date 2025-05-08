output "load_balancer_dns" {
  description = "Load Balancer DNS"
  value       = aws_lb.load_balancer.dns_name
}

output "proxy_sg" {
  description = "Proxy Instance Security Group"
  value       = aws_security_group.instance_sg.id
}
