data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}

resource "random_string" "deployment_id" {
  length  = 10
  special = false
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id                  = data.aws_caller_identity.current.account_id
  aws_region                  = data.aws_region.current.name
  deployment_id               = formatdate("YYYYMMDDhhmmss", timestamp())
  redis_instance_name         = "${var.deployment_name}-redis-${local.deployment_id}"
  redis_subnet_group_name     = "${var.deployment_name}-subnets-${local.deployment_id}"
  locust_leader_instance_name = "${var.deployment_name}-locust-leader-${local.deployment_id}"
  locust_node_instance_name   = "${var.deployment_name}-locust-node-${local.deployment_id}"
}

data "archive_file" "tests" {
  type        = "zip"
  source_dir  = "${path.module}/plans"
  output_path = "${path.module}/temp/tests.zip"
}

resource "aws_s3_object" "tests" {
  depends_on = [data.archive_file.tests]
  bucket     = var.s3_bucket
  key        = "${var.s3_bucket_key}${local.deployment_id}/tests.zip"
  source     = "${path.module}/temp/tests.zip"
  etag       = data.archive_file.tests.output_md5
}
