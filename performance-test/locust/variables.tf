variable "deployment_name" {
  description = "Deployment name"
  default     = "kivera-perf-test"
}

variable "nodes_count" {
  description = "Number of total nodes/instances"
  default     = 45
}

variable "leader_instance_type" {
  default = "t3.medium"
}

variable "nodes_instance_type" {
  default = "c5d.xlarge"
}

variable "leader_monitoring" {
  default = false
}

variable "nodes_monitoring" {
  default = false
}

variable "leader_associate_public_ip_address" {
  description = "Associate public IP address to the leader"
  type        = bool
  default     = false
}

variable "nodes_associate_public_ip_address" {
  description = "Associate public IP address to the nodes"
  type        = bool
  default     = false
}

variable "proxy_endpoint" {
  description = "Proxy endpoint for Locust to target"
  type        = string
}

variable "proxy_transparent_enabled" {
  description = "Enable if proxy is running in transparent mode"
  type        = bool
  default     = false
}

variable "s3_bucket" {
  description = "The bucket used to upload the tests/files"
}

variable "s3_bucket_key" {
  description = "The key/path to be used to upload the tests/files"
  default     = "/kivera/locust-perf-test/"
}

variable "vpc_id" {
  description = "VPC ID"
}

variable "public_subnet_id" {
  description = "Public Subnet ID"
}

variable "private_subnet_ids" {
  description = "Private Subnet ID"
  type        = list(string)
}

variable "ec2_key_pair" {
  description = "Name of EC2 key pair on AWS"
  default     = ""
}

variable "leader_username" {
  description = "Username used to connect to the Locust leader node"
  default     = "user"
}

variable "web_cidr_ingress_blocks" {
  description = "CIDR ingress for the leader"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "locust_max_users" {
  description = "Max number of Locust users"
  type        = number
  default     = 10000
}

variable "locust_spawn_rate" {
  description = "Rate at which Locust users spawn (per second)"
  type        = number
  default     = 50
}

variable "locust_run_time" {
  description = "Duration of the Locust test (minutes)"
  type        = number
  default     = 10
}

variable "user_wait_min" {
  description = "Max wait time between user requests (per second)"
  type        = number
  default     = 4
}

variable "user_wait_max" {
  description = "Min wait time between user requests (per second)"
  type        = number
  default     = 6
}

variable "proxy_public_cert" {
  description = "Public cert used by the proxy"
  default     = ""
}

variable "max_client_reuse" {
  description = "The maximum amount of times a client will be re-used in tests (0-n)"
  type        = number
  default     = 10
}

variable "test_timeout" {
  description = "The maximum amount of time (in secodns) a test is allowed to run before failing"
  type        = number
  default     = 60
}
