### Infra variables
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "kivera"

  validation {
    condition     = length(var.name_prefix) <= 10
    error_message = "The prefix name cannot exceed 10 characters"
  }
}

variable "region" {
  description = "Which region to deploy in"
  type        = string
  default     = "ap-southeast-2"
}

variable "vpc_id" {
  description = "Which VPC to deploy the proxy into"
  type        = string
}

variable "proxy_subnet_ids" {
  description = "Which Subnets to deploy the proxy into"
  type        = list(string)
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

variable "proxy_instance_type" {
  description = "The EC2 Instance Type of the proxy"
  type        = string
  default     = "c5d.xlarge"
}

variable "proxy_min_asg_size" {
  description = "Minimum number of instances in the Autoscaling Group"
  type        = number
  default     = 3
}

variable "proxy_max_asg_size" {
  description = "Maximum number of instances in the autoscaling group"
  type        = number
  default     = 12
}

variable "ec2_key_pair" {
  description = "Name of an existing EC2 KeyPair to enable SSH access to the instances"
  type        = string
}

variable "load_balancer_subnet_ids" {
  description = "Which Subnets to deploy the load balancer into"
  type        = list(string)
}

variable "load_balancer_internal" {
  description = "Enable to use an internal load balancer"
  type        = bool
  default     = true
}

variable "load_balancer_cross_zone" {
  description = "Enable for cross zone load balancing"
  type        = bool
  default     = true
}

variable "s3_bucket" {
  description = "The name of the bucket used to upload the tests/files"
  type        = string
  default     = ""
}

variable "s3_bucket_key" {
  description = "The key/path to be used to upload the tests/files"
  type        = string
  default     = "/kivera/proxy"
}

### Proxy variables
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

variable "external_ca" {
  description = "Enable to use an external CA for the proxy"
  type        = bool
  default     = false
}

variable "proxy_https" {
  description = "Enable to switch to https listener (port 8443)"
  type        = bool
  default     = false
}

variable "pca_arn" {
  description = "The ARN of the PCA certificate"
  type        = string
  default     = ""
}

variable "proxy_https_key" {
  description = "The private key used by the proxy to establish tls"
  type        = string
  default     = ""
}

variable "proxy_https_cert" {
  description = "The public certificate associated with the https private key"
  type        = string
  default     = ""
}

variable "proxy_log_to_kivera" {
  description = "Enable to send all logs to Kivera"
  type        = bool
  default     = true
}

variable "proxy_log_to_cloudwatch" {
  description = "Enable to send logs to Cloudwatch"
  type        = bool
  default     = true
}

variable "proxy_local_path" {
  description = "Path to a local proxy binary (takes precedence over proxy_version)"
  type        = string
  default     = ""
}

variable "proxy_log_group_retention" {
  description = "The number of days to retain proxy logs in CloudWatch Logs"
  type        = number
  default     = 30
}

variable "upstream_proxy" {
  description = "Enable to point towards upstream proxy and download it's cert"
  type        = bool
  default     = false
}

variable "upstream_proxy_endpoint" {
  description = "The endpoint for the upstream proxy"
  type        = string
  default     = ""
}

variable "upstream_proxy_port" {
  description = "Port for upstream proxy"
  type        = string
  default     = ""
}

variable "custom_domain_prefix" {
  description = "Route 53 record name"
  type        = string
  default     = ""
}

variable "custom_domain_zone_id" {
  description = "Route 53 zone id"
  type        = string
  default     = ""
}

### Cache variables
variable "cache_enabled" {
  description = "Whether to deploy and use a cache with the proxy"
  type        = bool
  default     = true
}

variable "cache_type" {
  description = "What type of cache to deploy"
  type        = string
  default     = "redis"

  validation {
    condition     = contains(["redis"], var.cache_type)
    error_message = "Allowed value(s) for cache_type: \"redis\"."
  }
}

variable "cache_default_username" {
  description = "The username used to connect to the cache as default user"
  type        = string
  default     = "new-default-user"
}

variable "cache_default_password" {
  description = "The password used to connect to the cache as default user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cache_kivera_username" {
  description = "The username used to connect to the cache as the kivera proxy user"
  type        = string
  default     = "kivera"
}

variable "cache_kivera_password" {
  description = "The password used to connect to the cache as the kivera proxy user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cache_user_group" {
  description = "The user group for the cache"
  type        = string
  default     = "kivera"
}

variable "cache_iam_auth" {
  description = "Enable to use iam auth to connect to the cache"
  type        = bool
  default     = false
}

variable "cache_subnet_ids" {
  description = "Which Subnets to deploy the cache into"
  type        = list(string)
  default     = []
}

variable "cache_instance_type" {
  description = "The instance type of the cache"
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

### Datadog agent variables
variable "datadog_secret_arn" {
  description = "The arn for the Datadog API key secret (required if enabled_datadog_agent is true)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "datadog_trace_sampling_rate" {
  description = "The samping rate Datadog uses for tracing"
  type        = number
  default     = 0.2
}

variable "enable_datadog_tracing" {
  description = "Enable trace metrics to be sent to Datadog"
  type        = bool
  default     = false
}

variable "enable_datadog_profiling" {
  description = "Enable profile metrics to be sent to Datadog"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable cloudwatch dashboard for Kivera proxy"
  type        = bool
  default     = true
}
