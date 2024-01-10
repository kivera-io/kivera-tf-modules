data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

locals {
  proxy_credentials_secret_arn = var.proxy_credentials != "" ? aws_secretsmanager_secret_version.proxy_credentials_version[0].arn : var.proxy_credentials_secret_arn
  proxy_private_key_secret_arn = var.proxy_private_key != "" ? aws_secretsmanager_secret_version.proxy_private_key_version[0].arn : var.proxy_private_key_secret_arn
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
          "sts:AssumeRole"
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
          Action = "secretsmanager:GetSecretValue"
          Effect = "Allow"
          Resource = [
            local.proxy_credentials_secret_arn,
            local.proxy_private_key_secret_arn,
            var.ddog_secret_arn
          ]
        },
        {
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:CreateMultipartUpload"
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:s3:::kivera-perf-test-bucket/*"
          ]
        },
      ]
    })
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = "${var.name_prefix}-instance-"
  role        = aws_iam_role.instance_role.name
}

resource "aws_security_group" "load_balancer_sg" {
  name_prefix = "${var.name_prefix}-lb-"
  vpc_id      = var.vpc_id
  description = "Access to the load balancer"
}

resource "aws_vpc_security_group_ingress_rule" "load_balancer_ssh_rule" {
  security_group_id = aws_security_group.load_balancer_sg.id
  cidr_ipv4         = var.proxy_allowed_ssh_range
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "load_balancer_traffic_rule" {
  security_group_id = aws_security_group.load_balancer_sg.id
  cidr_ipv4         = var.proxy_allowed_ingress_range
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_ingress_rule" "load_balancer_mgmt_rule" {
  security_group_id = aws_security_group.load_balancer_sg.id
  cidr_ipv4         = var.proxy_allowed_ingress_range
  ip_protocol       = "tcp"
  from_port         = 8090
  to_port           = 8090
}

resource "aws_vpc_security_group_egress_rule" "load_balancer_egress_rule" {
  security_group_id = aws_security_group.load_balancer_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_security_group" "instance_sg" {
  name_prefix = "${var.name_prefix}-instance-"
  vpc_id      = var.vpc_id
  description = "Access to the proxy instances"
}

resource "aws_vpc_security_group_ingress_rule" "instance_ssh_rule" {
  security_group_id            = aws_security_group.instance_sg.id
  referenced_security_group_id = aws_security_group.load_balancer_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

resource "aws_vpc_security_group_ingress_rule" "instance_traffic_rule" {
  security_group_id            = aws_security_group.instance_sg.id
  referenced_security_group_id = aws_security_group.load_balancer_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_ingress_rule" "instance_mgmt_rule" {
  security_group_id            = aws_security_group.instance_sg.id
  referenced_security_group_id = aws_security_group.load_balancer_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 8090
  to_port                      = 8090
}

resource "aws_vpc_security_group_egress_rule" "instance_egress_rule" {
  security_group_id = aws_security_group.instance_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_launch_template" "launch_template" {
  name_prefix   = "${var.name_prefix}-instance-"
  image_id      = data.aws_ami.latest.id
  instance_type = var.proxy_instance_type
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance_profile.arn
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
    }
  }
  vpc_security_group_ids = [
    aws_security_group.instance_sg.id
  ]
  key_name  = var.key_pair_name
  user_data = base64encode(data.template_file.proxy_user_data.rendered)
}

data "template_file" "proxy_user_data" {
  template = file("${path.module}/data/user-data.sh.tpl")
  vars = {
    enable_datadog_tracing       = var.enable_datadog_tracing
    enable_datadog_profiling     = var.enable_datadog_profiling
    ddog_secret_arn              = var.ddog_secret_arn
    ddog_trace_sampling_rate     = var.ddog_trace_sampling_rate
    proxy_local_path             = var.proxy_local_path
    proxy_version                = var.proxy_version
    proxy_cert_type              = var.proxy_cert_type
    proxy_public_cert            = var.proxy_public_cert
    proxy_redis_cache_addr       = local.redis_cache_addr
    proxy_credentials_secret_arn = local.proxy_credentials_secret_arn
    proxy_private_key_secret_arn = local.proxy_private_key_secret_arn
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
  health_check_grace_period = 180
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns = [
    aws_lb_target_group.traffic_target_group.arn,
    aws_lb_target_group.management_target_group.arn
  ]
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

resource "aws_lb_target_group" "traffic_target_group" {
  name = "${var.name_prefix}-traffic"
  health_check {
    enabled             = true
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "TCP"
  }
  port                 = 8080
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  deregistration_delay = 5
  target_type          = "instance"
}

resource "aws_lb_listener" "traffic_listener" {
  default_action {
    target_group_arn = aws_lb_target_group.traffic_target_group.arn
    type             = "forward"
  }
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 8080
  protocol          = "TCP"
}

resource "aws_lb_target_group" "management_target_group" {
  name = "${var.name_prefix}-mgmt"
  health_check {
    enabled             = true
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    port                = 8090
    protocol            = "HTTP"
    path                = "/version"
    matcher             = 200
  }
  port                 = 8090
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  deregistration_delay = 5
  target_type          = "instance"
}

resource "aws_lb_listener" "management_listener" {
  default_action {
    target_group_arn = aws_lb_target_group.management_target_group.arn
    type             = "forward"
  }
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 8090
  protocol          = "TCP"
}

resource "aws_lb" "load_balancer" {
  name               = "${var.name_prefix}-load-balancer"
  internal           = var.load_balancer_internal
  subnets            = var.subnet_ids
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.load_balancer_sg.id
  ]
  enable_cross_zone_load_balancing = true
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

resource "aws_s3_bucket" "bucket" {
  bucket = "${var.name_prefix}-bucket"
}

data "archive_file" "proxy_binary" {
  count       = var.proxy_local_path != "" ? 1 : 0
  type        = "zip"
  source_file = var.proxy_local_path
  output_path = "${path.module}/temp/proxy.zip"
}

resource "aws_s3_object" "proxy_binary" {
  count      = var.proxy_local_path != "" ? 1 : 0
  depends_on = [data.archive_file.proxy_binary]
  bucket     = aws_s3_bucket.bucket.id
  key        = "locust-tests/proxies/proxy.zip"
  source     = "${path.module}/temp/proxy.zip"
  etag       = data.archive_file.proxy_binary[count.index].output_md5
}

locals {
  redis_instance_name     = "${var.name_prefix}-redis"
  redis_subnet_group_name = "${var.name_prefix}-subnets"
  redis_cache_addr        = var.enable_redis_cache ? aws_elasticache_cluster.redis[0].cache_nodes[0].address : ""
}

resource "aws_elasticache_cluster" "redis" {
  count = var.enable_redis_cache ? 1 : 0

  cluster_id           = local.redis_instance_name
  engine               = "redis"
  engine_version       = 7.1
  node_type            = "cache.t3.medium"
  parameter_group_name = "default.redis7"
  num_cache_nodes      = 1

  subnet_group_name  = aws_elasticache_subnet_group.redis[count.index].name
  security_group_ids = [aws_security_group.redis[count.index].id]
}

resource "aws_elasticache_subnet_group" "redis" {
  count = var.enable_redis_cache ? 1 : 0

  name       = local.redis_subnet_group_name
  subnet_ids = [var.private_subnet_id]
}

resource "aws_security_group" "redis" {
  count = var.enable_redis_cache ? 1 : 0

  name        = "${var.name_prefix}-redis-sg"
  description = "Security Group for redis instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.instance_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
