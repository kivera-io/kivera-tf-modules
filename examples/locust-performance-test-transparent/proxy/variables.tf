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

variable "proxy_instance_type" {
  description = "The EC2 Instance Type of the proxy"
  type        = string
  default     = "t3.medium"
}

variable "ec2_key_pair" {
  description = "Name of an existing EC2 KeyPair to enable SSH access to the instances"
  type        = string
  default     = ""
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

variable "cache_enabled" {
  description = "Whether to deploy and use a cache"
  type        = bool
  default     = true
}

variable "s3_bucket" {
  description = "The name of the bucket used to upload the tests/files"
  type        = string
}
