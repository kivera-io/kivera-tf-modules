locals {
  stack_name = "kivera-network"
}

variable "availability_zone1" {
  description = "Availability Zone to use for the Public Subnet 1 in the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "egress_subnet_cidr" {
  description = "CIDR block for the egress subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "inspection_subnet_cidr" {
  description = "CIDR block for the inspection subnet"
  type        = string
  default     = "10.10.2.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.10.3.0/24"
}

variable "access_location" {
  description = "Enter desired Network CIDR to access Bastion Host. Default is set to access from anywhere (0.0.0.0/0) and it is not recommended"
  type        = string
  default     = "0.0.0.0/0"
}
