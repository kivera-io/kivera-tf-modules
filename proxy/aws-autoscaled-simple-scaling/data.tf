provider "aws" {
  region = var.region
}

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_region" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false // aws tf provider bug with handling upper case
  special = false
}

resource "random_password" "default_pass" {
  length  = 16
  special = false
}

resource "random_password" "kivera_pass" {
  length  = 16
  special = false
}

locals {
  name_suffix                        = random_string.suffix.result
  proxy_s3_path                      = var.proxy_local_path != "" ? "s3://${var.s3_bucket}${var.s3_bucket_key}/proxy.zip" : ""
  proxy_credentials_secret_arn       = var.proxy_credentials != "" ? aws_secretsmanager_secret_version.proxy_credentials_version[0].arn : var.proxy_credentials_secret_arn
  proxy_private_key_secret_arn       = var.proxy_private_key != "" ? aws_secretsmanager_secret_version.proxy_private_key_version[0].arn : var.proxy_private_key_secret_arn
  proxy_https_private_key_secret_arn = var.proxy_https_key != "" ? aws_secretsmanager_secret_version.proxy_https_private_key_version[0].arn : ""
  cache_default_pass                 = var.cache_default_password != "" ? var.cache_default_password : random_password.default_pass.result
  cache_kivera_pass                  = var.cache_kivera_password != "" ? var.cache_kivera_password : random_password.kivera_pass.result
  redis_enabled                      = var.cache_enabled && var.cache_type == "redis" ? true : false
  redis_endpoint                     = local.redis_enabled && var.serverless_cache ? aws_elasticache_serverless_cache.redis[0].endpoint[0].address : aws_elasticache_replication_group.redis[0].configuration_endpoint_address
  redis_default_connection_string    = local.redis_enabled ? sensitive("rediss://default:${local.cache_default_pass}@${local.redis_endpoint}:6379") : ""
  redis_kivera_connection_string     = local.redis_enabled ? sensitive("rediss://${var.cache_kivera_username}:${local.cache_kivera_pass}@${local.redis_endpoint}:6379") : ""
  redis_kivera_iam_connection_string = local.redis_enabled ? sensitive("rediss://${var.cache_kivera_username}-iam@${local.redis_endpoint}:6379") : ""
  redis_connection_string_secret_arn = local.redis_enabled ? aws_secretsmanager_secret_version.redis_kivera_connection_string_version[0].arn : ""
  cache_cluster_name                 = var.cache_enabled && var.serverless_cache ? aws_elasticache_serverless_cache.redis[0].name : aws_elasticache_replication_group.redis[0].id
}

data "archive_file" "proxy_binary" {
  count = var.proxy_local_path != "" ? 1 : 0

  type        = "zip"
  source_file = var.proxy_local_path
  output_path = "${path.module}/temp/proxy.zip"
}

resource "aws_s3_object" "proxy_binary" {
  count = var.proxy_local_path != "" ? 1 : 0

  depends_on = [data.archive_file.proxy_binary]
  bucket     = var.s3_bucket
  key        = "${var.s3_bucket_key}/proxy.zip"
  source     = "${path.module}/temp/proxy.zip"
  etag       = data.archive_file.proxy_binary[count.index].output_md5

  lifecycle {
    precondition {
      condition     = var.s3_bucket != "" && var.s3_bucket_key != ""
      error_message = "s3_bucket and s3_bucket_key must be provided if proxy_local_path is provided"
    }
  }
}

resource "aws_route53_record" "lb_record" {
  count = (var.custom_domain_zone_id != "" || var.custom_domain_prefix != "") ? 1 : 0

  zone_id = var.custom_domain_zone_id
  name    = var.custom_domain_prefix
  type    = "A"
  alias {
    name                   = aws_lb.load_balancer.dns_name
    zone_id                = aws_lb.load_balancer.zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition     = var.custom_domain_zone_id != "" && var.custom_domain_prefix != ""
      error_message = "both custom_domain_zone_id and custom_domain_prefix must be provided to create a custom domain for proxy"
    }
  }
}

resource "aws_cloudwatch_dashboard" "proxy_dashbaord" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0

  dashboard_name = "${var.name_prefix}-dashboard-${local.name_suffix}"

  dashboard_body = templatefile("${path.module}/data/proxy-cw-dashboard.json", {
    log_group_name   = "${var.name_prefix}-proxy-${local.name_suffix}"
    log_group_region = data.aws_region.current.region
  })
}
