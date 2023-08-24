output "load_balancer_dns" {
  description = "Load Balancer DNS"
  value       = aws_lb.load_balancer.dns_name
}
