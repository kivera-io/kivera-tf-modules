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
