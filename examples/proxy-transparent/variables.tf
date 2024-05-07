### PROXY VARIABLES ###
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
  default     = "c5d.xlarge"
}

variable "cache_enabled" {
  description = "Whether to deploy and use a cache"
  type        = bool
  default     = true
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

variable "datadog_secret_arn" {
  description = "The arn for the Data Dog API key secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_datadog_tracing" {
  description = "Enable trace metrics to be sent to datadog"
  type        = bool
  default     = false
}

variable "enable_datadog_profiling" {
  description = "Enable profile metrics to be sent to datatog"
  type        = bool
  default     = false
}

### AWS INFRA VARIABLES
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "kivera"

  validation {
    condition     = length(var.name_prefix) <= 10
    error_message = "The prefix name cannot exceed 10 characters"
  }
}

variable "ec2_key_pair" {
  description = "Name of an existing EC2 KeyPair to enable SSH access to the instances"
  type        = string
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

variable "proxy_local_path" {
  description = "Path to a local proxy binary (takes precedence over proxy_version)"
  type        = string
  default     = ""
}

variable "s3_bucket" {
  description = "The name of the bucket used to upload the tests/files"
  type        = string
}

variable "s3_bucket_key" {
  description = "The key/path to be used to upload the tests/files"
  type        = string
  default     = "/kivera/proxy"
}

variable "load_balancer_cross_zone" {
  description = "Enable for cross zone load balancing"
  type        = bool
  default     = false
}