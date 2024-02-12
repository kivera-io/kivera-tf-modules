variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string(7)
  default     = "kivera"
}

variable "proxy_version" {
  description = "The version of the proxy to deploy"
  type        = string
  default     = "latest"
}

variable "proxy_credentials" {
  description = "The proxy credentials as a json string (required if proxy_credentials_secret_arn is not provided)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxy_credentials_secret_arn" {
  description = "The ARN of the proxy credentials secret (required if proxy_credentials is not provided)"
  type        = string
  default     = ""
}

variable "proxy_private_key" {
  description = "The private key to be used by the proxy (required if proxy_private_key_secret_arn is not provided)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxy_private_key_secret_arn" {
  description = "The ARN of the proxy private key secret (required if proxy_private_key is not provided)"
  type        = string
  default     = ""
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

variable "load_balancer_subnet_ids" {
  description = "Which Subnets to deploy the load balancer into"
  type        = list(string)
}

variable "proxy_subnet_ids" {
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

variable "proxy_log_group_retention" {
  description = "The number of days to retain proxy logs in CloudWatch Logs"
  type        = number
  default     = 14
}

variable "redis_cache_enabled" {
  description = "Whether to deploy and use a Redis cache"
  type        = bool
  default     = true
}

variable "redis_subnet_ids" {
  description = "Which Subnets to deploy the Redis cluster into"
  type        = list(string)
}

variable "redis_instance_type" {
  description = "The ElastiCache Instance Type of the Redis nodes"
  type        = string
  default     = "cache.t3.medium"
}

variable "redis_num_node_groups" {
  description = "The number of node groups in the Redis cluster"
  type        = number
  default     = 1
}

variable "redis_replicas_per_node_group" {
  description = "The number of replicas for each node groups in the Redis cluster"
  type        = number
  default     = 2
}
