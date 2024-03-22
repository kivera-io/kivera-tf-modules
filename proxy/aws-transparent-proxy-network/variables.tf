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

variable "egress_subnet_cidrs" {
  description = "List of CIDR blocks for the egress subnet"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]

  validation {
    condition     = length(var.egress_subnet_cidrs) >= 3
    error_message = "egress_subnet_cidrs must include at least 3 CIDR blocks"
  }
}

variable "inspection_subnet_cidrs" {
  description = "List of CIDR blocks for the inspection subnet"
  type        = list(string)
  default     = ["10.10.4.0/24", "10.10.5.0/24", "10.10.6.0/24"]

  validation {
    condition     = length(var.inspection_subnet_cidrs) >= 3
    error_message = "inspection_subnet_cidrs must include at least 3 CIDR blocks"
  }
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for the private subnet"
  type        = list(string)
  default     = ["10.10.7.0/24", "10.10.8.0/24", "10.10.9.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 3
    error_message = "private_subnet_cidrs must include at least 3 CIDR blocks"
  }
}

variable "access_location" {
  description = "Enter desired Network CIDR to access Bastion Host. Default is set to access from anywhere (0.0.0.0/0) and it is not recommended"
  type        = string
  default     = "0.0.0.0/0"
}
