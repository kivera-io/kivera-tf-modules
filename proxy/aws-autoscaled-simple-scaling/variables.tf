variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "kivera"
}

variable "proxy_version" {
  description = "The version of the proxy to deploy"
  type        = string
  default     = "latest"
}

variable "proxy_credentials" {
  description = "The proxy credentials as a json string"
  type        = string
  sensitive   = true
}

variable "proxy_private_key" {
  description = "The private key to be used by the proxy"
  type        = string
  sensitive   = true
}

variable "proxy_public_cert" {
  description = "The public certificate associated with the proxies private key"
  type        = string
}

variable "proxy_cert_type" {
  description = "The type of public certificate provided"
  type        = string
  default     = "ecdsa"
}

variable "proxy_instance_type" {
  description = "The EC2 Instance Type of the proxy"
  type        = string
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 KeyPair to enable SSH access to the instances"
  type        = string
}

variable "vpc_id" {
  description = "Which VPC to deploy the proxy into"
  type        = string
}

variable "subnet_ids" {
  description = "Which Subnets to deploy the proxy into"
  type        = list(string)
}

variable "load_balancer_internal" {
  description = "Which load balancer scheme to use"
  type        = bool
  default     = true
}

variable "proxy_allowed_ingress_range" {
  description = "IP range allowed to connect to proxy"
  type        = string
  default     = "10.0.0.0/8"
}

variable "proxy_allowed_ssh_range" {
  description = "IP range allowed to SSH to proxy"
  type        = string
  default     = "10.0.0.0/8"
}

variable "proxy_min_asg_size" {
  description = "Minimum instances in the Autoscaling Group"
  type        = number
  default     = 3
}

variable "proxy_max_asg_size" {
  description = "Maximum number of instances in the autoscaling group"
  type        = number
  default     = 12
}
