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
  key_name = var.ec2_key_pair
  user_data = base64encode(templatefile("${path.module}/data/user-data.sh.tpl", {
    instance_name                = "${var.name_prefix}-proxy"
    upstream_proxy_endpoint      = var.upstream_proxy_endpoint
    upstream_proxy               = var.upstream_proxy
    upstream_proxy_port          = var.upstream_proxy_port
    proxy_version                = var.proxy_version
    proxy_s3_path                = local.proxy_s3_path
    proxy_cert_type              = var.proxy_cert_type
    proxy_public_cert            = var.proxy_public_cert
    proxy_credentials_secret_arn = local.proxy_credentials_secret_arn
    proxy_private_key_secret_arn = local.proxy_private_key_secret_arn
    external_ca                  = var.external_ca
    pca_arn                      = var.pca_arn
    proxy_https                  = var.proxy_https
    proxy_https_cert             = var.proxy_https_cert
    proxy_https_key_arn          = local.proxy_https_private_key_secret_arn
    proxy_log_to_kivera          = var.proxy_log_to_kivera
    proxy_log_to_cloudwatch      = var.proxy_log_to_cloudwatch
    redis_connection_string_arn  = local.redis_connection_string_secret_arn
    redis_iam_connection_string  = local.redis_kivera_iam_connection_string
    cache_cluster_name           = local.cache_cluster_name
    cache_iam_auth               = var.cache_iam_auth
    region                       = data.aws_region.current.region
    log_group_name               = "${var.name_prefix}-proxy-${local.name_suffix}"
    log_group_retention_in_days  = var.proxy_log_group_retention
    enable_datadog_tracing       = var.enable_datadog_tracing
    enable_datadog_profiling     = var.enable_datadog_profiling
    cache_enabled                = var.cache_enabled
    datadog_secret_arn           = var.datadog_secret_arn
    datadog_trace_sampling_rate  = var.datadog_trace_sampling_rate
  }))
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
  vpc_zone_identifier       = var.proxy_subnet_ids
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
  name = "${var.name_prefix}-traffic-${local.name_suffix}"
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
  name = "${var.name_prefix}-mgmt-${local.name_suffix}"
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
  name               = "${var.name_prefix}-lb-${local.name_suffix}"
  internal           = var.load_balancer_internal
  subnets            = var.load_balancer_subnet_ids
  load_balancer_type = "network"
  security_groups = [
    aws_security_group.load_balancer_sg.id
  ]
  enable_cross_zone_load_balancing = var.load_balancer_cross_zone
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
