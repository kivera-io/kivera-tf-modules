data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "random_string" "suffix" {
  length  = 10
  special = false
}

locals {
  suffix                       = random_string.suffix.result
  s3_path                      = "s3://${var.s3_bucket}${var.s3_bucket_key}"
  glb_s3_path                  = "${local.s3_path}/gwlbtun.service"
  tunneler_s3_path             = "${local.s3_path}/tunnel-handler.sh"
  proxy_s3_path                = var.proxy_local_path != "" ? "${local.s3_path}/proxy.zip" : ""
  proxy_credentials_secret_arn = var.proxy_credentials != "" ? aws_secretsmanager_secret_version.proxy_credentials_version[0].arn : var.proxy_credentials_secret_arn
  proxy_private_key_secret_arn = var.proxy_private_key != "" ? aws_secretsmanager_secret_version.proxy_private_key_version[0].arn : var.proxy_private_key_secret_arn
  redis_enabled                = var.cache_enabled && var.cache_type == "redis" ? true : false
  redis_connection_string      = local.redis_enabled ? "rediss://${aws_elasticache_replication_group.redis[0].configuration_endpoint_address}:6379" : ""
}

resource "aws_secretsmanager_secret" "proxy_credentials" {
  count       = var.proxy_credentials != "" ? 1 : 0
  name_prefix = "${var.name_prefix}-credentials-"
}

resource "aws_secretsmanager_secret_version" "proxy_credentials_version" {
  count         = var.proxy_credentials != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.proxy_credentials[0].id
  secret_string = var.proxy_credentials
}

resource "aws_secretsmanager_secret" "proxy_private_key" {
  count       = var.proxy_private_key != "" ? 1 : 0
  name_prefix = "${var.name_prefix}-private-key-"
}

resource "aws_secretsmanager_secret_version" "proxy_private_key_version" {
  count         = var.proxy_private_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.proxy_private_key[0].id
  secret_string = var.proxy_private_key
}

resource "aws_iam_role" "instance_role" {
  name_prefix = "${var.name_prefix}-instance-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole",
        ]
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]
  inline_policy {
    name = "${var.name_prefix}-get-secrets"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = "ec2:ModifyInstanceAttribute"
          Effect   = "Allow"
          Resource = ["*"]
          Condition = {
            "StringEquals" : { "aws:ResourceTag/Name" : "${var.name_prefix}-proxy" }
          }
        },
        {
          Action = "secretsmanager:GetSecretValue"
          Effect = "Allow"
          Resource = [
            local.proxy_credentials_secret_arn,
            local.proxy_private_key_secret_arn
          ]
        },
        {
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:CreateMultipartUpload",
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:s3:::${var.s3_bucket}/*"
          ]
        },
      ]
    })
  }
}

resource "aws_iam_role_policy" "instance_default_policies" {
  count = var.enable_datadog_profiling || var.enable_datadog_tracing ? 1 : 0

  name = "proxy_default_policies"
  role = aws_iam_role.instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "secretsmanager:GetSecretValue"
        Effect = "Allow"
        Resource = [
          var.datadog_secret_arn
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = "${var.name_prefix}-instance-"
  role        = aws_iam_role.instance_role.name
}

resource "aws_security_group" "instance_sg" {
  name_prefix = "${var.name_prefix}-instance-"
  vpc_id      = var.vpc_id
  description = "Access to the proxy instances"
}

resource "aws_vpc_security_group_ingress_rule" "instance_ingress_rule" {
  security_group_id = aws_security_group.instance_sg.id
  ip_protocol       = -1
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "instance_egress_rule" {
  security_group_id = aws_security_group.instance_sg.id
  ip_protocol       = -1
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_s3_object" "glb_file" {
  bucket = var.s3_bucket
  key    = "${var.s3_bucket_key}/gwlbtun.service"
  source = "${path.module}/data/gwlbtun.service"
}

resource "aws_s3_object" "tunneler_file" {
  bucket = var.s3_bucket
  key    = "${var.s3_bucket_key}/tunnel-handler.sh"
  source = "${path.module}/data/tunnel-handler.sh"
}

resource "aws_launch_template" "launch_template" {
  name_prefix   = "${var.name_prefix}-instance-"
  image_id      = data.aws_ami.latest.id
  instance_type = var.proxy_instance_type
  key_name      = var.key_pair_name
  user_data = base64encode(templatefile("${path.module}/data/user-data.sh.tpl", {
    proxy_version                = var.proxy_version
    proxy_s3_path                = local.proxy_s3_path
    proxy_cert_type              = var.proxy_cert_type
    proxy_public_cert            = var.proxy_public_cert
    proxy_credentials_secret_arn = local.proxy_credentials_secret_arn
    proxy_private_key_secret_arn = local.proxy_private_key_secret_arn
    proxy_log_to_kivera          = var.proxy_log_to_kivera
    proxy_log_to_cloudwatch      = var.proxy_log_to_cloudwatch
    redis_connection_string      = local.redis_connection_string
    glb_file                     = local.glb_s3_path
    tunneler_file                = local.tunneler_s3_path
    log_group_name               = "${var.name_prefix}-proxy-${local.suffix}"
    log_group_retention_in_days  = var.proxy_log_group_retention
    enable_datadog_tracing       = var.enable_datadog_tracing
    enable_datadog_profiling     = var.enable_datadog_profiling
    datadog_secret_arn           = var.datadog_secret_arn
    datadog_trace_sampling_rate  = var.datadog_trace_sampling_rate
  }))
  vpc_security_group_ids = [
    aws_security_group.instance_sg.id
  ]
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance_profile.arn
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
    }
  }
}

resource "aws_autoscaling_group" "auto_scaling_group" {
  name_prefix = "${var.name_prefix}-"
  launch_template {
    id      = aws_launch_template.launch_template.id
    version = aws_launch_template.launch_template.latest_version
  }
  min_size                  = var.proxy_min_asg_size
  max_size                  = var.proxy_max_asg_size
  health_check_type         = "ELB"
  health_check_grace_period = 480
  vpc_zone_identifier       = var.proxy_subnet_ids
  target_group_arns         = [aws_lb_target_group.glb_target_group.arn]
  instance_refresh {
    strategy = "Rolling"
    triggers = ["tag"]
    preferences {
      auto_rollback          = true
      min_healthy_percentage = 100
    }
  }
  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-proxy"
    propagate_at_launch = true
  }
}

resource "aws_lb" "glb" {
  name                             = "${var.name_prefix}-glb-${local.suffix}"
  load_balancer_type               = "gateway"
  subnets                          = var.proxy_subnet_ids
  enable_cross_zone_load_balancing = var.cross_zone_lb
}

resource "aws_lb_target_group" "glb_target_group" {
  name                 = "${var.name_prefix}-glb-tg"
  vpc_id               = var.vpc_id
  port                 = 6081
  protocol             = "GENEVE"
  target_type          = "instance"
  deregistration_delay = 20
  health_check {
    enabled             = true
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
    port                = 8090
    protocol            = "HTTP"
    path                = "/version"
  }
}

resource "aws_lb_listener" "glb_listener" {
  load_balancer_arn = aws_lb.glb.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.glb_target_group.arn
  }

  tags = {
    Name = "${var.name_prefix}-glb-listner"
  }
}

resource "aws_vpc_endpoint_service" "vpc_endpoint_service" {
  gateway_load_balancer_arns = [aws_lb.glb.arn]
  acceptance_required        = false
}

resource "aws_vpc_endpoint" "glb_endpoint" {
  vpc_id            = var.vpc_id
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [var.private_subnet_ids[0]]
  service_name      = aws_vpc_endpoint_service.vpc_endpoint_service.service_name

  tags = {
    Name = "${var.name_prefix}-glb-endpoint"
  }
}

resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "${var.name_prefix}-scale-up"
  scaling_adjustment     = 3
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 180
  autoscaling_group_name = aws_autoscaling_group.auto_scaling_group.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm_high" {
  alarm_name         = "${var.name_prefix}-cpu-alarm-high"
  alarm_description  = "Alarm if CPU too high"
  statistic          = "Average"
  threshold          = 70
  period             = 10
  evaluation_periods = 3
  alarm_actions = [
    aws_autoscaling_policy.scale_up_policy.arn
  ]
  namespace   = "kivera"
  metric_name = "cpu_usage_active"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.auto_scaling_group.name
  }
  comparison_operator = "GreaterThanThreshold"
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "${var.name_prefix}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 30
  autoscaling_group_name = aws_autoscaling_group.auto_scaling_group.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm_low" {
  alarm_name         = "${var.name_prefix}-cpu-alarm-low"
  alarm_description  = "Alarm if CPU too low"
  statistic          = "Average"
  threshold          = 30
  evaluation_periods = 10
  period             = 30
  alarm_actions = [
    aws_autoscaling_policy.scale_down_policy.arn
  ]
  namespace   = "kivera"
  metric_name = "cpu_usage_active"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.auto_scaling_group.name
  }
  comparison_operator = "LessThanThreshold"
}

data "aws_s3_bucket" "bucket" {
  bucket = var.s3_bucket
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
  bucket     = data.aws_s3_bucket.bucket.id
  key        = "${var.s3_bucket_key}/proxy.zip"
  source     = "${path.module}/temp/proxy.zip"
  etag       = data.archive_file.proxy_binary[count.index].output_md5
}

resource "aws_security_group" "redis_sg" {
  count = local.redis_enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-redis-"
  vpc_id      = var.vpc_id
  description = "Access to the Redis cache"
}

resource "aws_vpc_security_group_ingress_rule" "redis_ingress_rule" {
  count = local.redis_enabled ? 1 : 0

  security_group_id            = aws_security_group.redis_sg[0].id
  referenced_security_group_id = aws_security_group.instance_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}

resource "aws_vpc_security_group_egress_rule" "redis_egress_rule" {
  count = local.redis_enabled ? 1 : 0

  security_group_id = aws_security_group.redis_sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_elasticache_subnet_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  name       = "${var.name_prefix}-subnet-group-${local.suffix}"
  subnet_ids = var.cache_subnet_ids

  lifecycle {
    precondition {
      condition     = length(var.cache_subnet_ids) > 0
      error_message = "cache_subnet_ids must be provided if cache_enabled is true"
    }
  }
}

resource "aws_elasticache_replication_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  replication_group_id = "${var.name_prefix}-redis-${local.suffix}"
  description          = "Redis Cache for Kivera proxy"

  node_type            = var.cache_instance_type
  engine_version       = 7.1
  parameter_group_name = "default.redis7.cluster.on"

  port               = 6379
  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.redis_sg[0].id]

  multi_az_enabled           = true
  num_node_groups            = var.redis_num_node_groups
  replicas_per_node_group    = var.redis_replicas_per_node_group
  automatic_failover_enabled = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  apply_immediately = true
}
