terraform {
  required_version = ">= 0.13.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.30.0"
    }

  }
}

provider "aws" {
  region = "ap-southeast-2"
}
