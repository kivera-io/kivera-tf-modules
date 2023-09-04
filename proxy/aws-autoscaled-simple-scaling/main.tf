data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
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
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ]
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
  vpc_security_group_ids = [
    aws_security_group.instance_sg.id
  ]
  key_name = var.key_pair_name
  user_data = base64encode(
    <<EOT
#!/bin/bash -ex
STATE=0

export KIVERA_BIN_PATH=/opt/kivera/bin
export KIVERA_CREDENTIALS=/opt/kivera/etc/credentials.json
export KIVERA_CA_CERT=/opt/kivera/etc/ca-cert.pem
export KIVERA_CA=/opt/kivera/etc/ca.pem
export KIVERA_CERT_TYPE=${var.proxy_cert_type}
export KIVERA_LOGS_FILE=/opt/kivera/var/log/proxy.log

mkdir -p $KIVERA_BIN_PATH /opt/kivera/etc/ /opt/kivera/var/log/

echo '${var.proxy_credentials}' > $KIVERA_CREDENTIALS
echo '${var.proxy_public_cert}' > $KIVERA_CA_CERT
echo '${var.proxy_private_key}' > $KIVERA_CA

groupadd -r kivera
useradd -mrg kivera kivera
useradd -g kivera td-agent

wget https://download.kivera.io/binaries/proxy/linux/amd64/kivera-${var.proxy_version}.tar.gz -O proxy.tar.gz
tar -xvzf proxy.tar.gz -C /opt/kivera
cp $KIVERA_BIN_PATH/linux/amd64/kivera $KIVERA_BIN_PATH/kivera
chmod 0755 $KIVERA_BIN_PATH/kivera
chown -R kivera:kivera /opt/kivera

yum install amazon-cloudwatch-agent -y

curl -L https://toolbelt.treasuredata.com/sh/install-amazon2-td-agent4.sh | sh
td-agent-gem install -N fluent-plugin-out-kivera

cat << EOF | tee /etc/systemd/system/kivera.service
[Unit]
Description=Kivera Proxy

[Service]
User=kivera
WorkingDirectory=$KIVERA_BIN_PATH
ExecStart=/usr/bin/sh -c "$KIVERA_BIN_PATH/kivera | tee -a $KIVERA_LOGS_FILE"
Restart=always
Environment=KIVERA_CREDENTIALS=$KIVERA_CREDENTIALS
Environment=KIVERA_CA_CERT=$KIVERA_CA_CERT
Environment=KIVERA_CA=$KIVERA_CA
Environment=KIVERA_CERT_TYPE=$KIVERA_CERT_TYPE

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /etc/systemd/system/td-agent.service.d/

cat << EOF | tee /etc/systemd/system/td-agent.service.d/override.conf
[Service]
Group=kivera
EOF

cat << EOF | tee /etc/td-agent/td-agent.conf
<source>
  @type tail
  tag kivera
  path $KIVERA_LOGS_FILE
  <parse>
    @type json
  </parse>
</source>
<match kivera>
  @type kivera
  config_file $KIVERA_CREDENTIALS
  bulk_request
  <buffer>
    flush_interval 1
    chunk_limit_size 1m
    flush_thread_interval 0.1
    flush_thread_burst_interval 0.01
    flush_thread_count 15
  </buffer>
</match>
EOF

cat << EOF | tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 1,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "kivera",
    "aggregation_dimensions": [
      ["InstanceId"],
      ["AutoScalingGroupName"]
    ],
    "append_dimensions": {
      "AutoScalingGroupName": "\$${aws:AutoScalingGroupName}",
      "ImageId": "\$${aws:ImageId}",
      "InstanceId": "\$${aws:InstanceId}",
      "InstanceType": "\$${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_active"
        ]
      }
    }
  }
}
EOF

systemctl enable amazon-cloudwatch-agent.service
systemctl start amazon-cloudwatch-agent.service
systemctl enable td-agent.service
systemctl start td-agent.service
systemctl enable kivera.service
systemctl start kivera.service

sleep 10

KIVERA_PROCESS=$(systemctl is-active kivera.service)
FLUENTD_PROCESS=$(systemctl is-active td-agent.service)
CLOUDWATCH_PROCESS=$(systemctl is-active amazon-cloudwatch-agent.service)

KIVERA_CONNECTIONS=$(lsof -i -P -n | grep kivera)
[[ $KIVERA_PROCESS -eq "active" && $KIVERA_CONNECTIONS == *"(ESTABLISHED)"* && $KIVERA_CONNECTIONS == *"(LISTEN)"* ]] \
  && echo "The Kivera service and connections appears to be healthy." \
  || (echo "The Kivera service and connections appear unhealthy." && STATE=1)

[[ $FLUENTD_PROCESS -eq "active" ]] \
  && echo "Fluentd service is running" \
  || (echo "Fluentd service is not running" && STATE=1)

[[ $CLOUDWATCH_PROCESS -eq "active" ]] \
  && echo "CloudWatch agent service is running" \
  || (echo "CloudWatch agent service is not running" && STATE=1)
EOT
  )
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
  health_check_grace_period = 300
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns = [
    aws_lb_target_group.traffic_target_group.arn,
    aws_lb_target_group.management_target_group.arn
  ]
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
    protocol            = "TCP"
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
  cooldown               = 120
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
