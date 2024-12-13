locals {
  stack_name = "kivera-network"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID"
  type        = string
}

variable "vpc_endpoint_id" {
  description = "Endpoint ID for VPC"
  type        = string
}

variable "private_subnet_rt_id" {
  description = "Endpoint ID for VPC"
  type        = string
}

variable "ec2_key_pair" {
  description = "Name of ec2 key pair"
  type        = string
  default     = ""
}

variable "proxy_public_cert" {
  description = "The public certificate associated with the proxies private key"
  type        = string
}
