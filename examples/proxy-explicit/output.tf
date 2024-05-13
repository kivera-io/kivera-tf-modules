output "load_balancer_dns" {
  description = "Load balancer DNS pointing towards proxy"
  value       = module.kivera-proxy.load_balancer_dns
}
