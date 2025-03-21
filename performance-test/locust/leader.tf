resource "aws_instance" "leader" {

  depends_on = [aws_s3_object.tests]

  ami = data.aws_ami.amazon_linux_2.id

  instance_type = var.leader_instance_type

  associate_public_ip_address = var.leader_associate_public_ip_address
  monitoring                  = var.leader_monitoring

  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.locust.id]

  iam_instance_profile = aws_iam_instance_profile.locust.name
  user_data = templatefile("${path.module}/data/leader-user-data.sh.tpl", {
    proxy_host          = var.proxy_endpoint
    locust_max_users    = var.locust_max_users
    locust_spawn_rate   = var.locust_spawn_rate
    locust_run_time     = var.locust_run_time
    user_wait_min       = var.user_wait_min
    user_wait_max       = var.user_wait_max
    deployment_name     = var.deployment_name
    s3_bucket           = var.s3_bucket
    s3_bucket_key       = var.s3_bucket_key
    deployment_id       = local.deployment_id
    leader_username     = var.leader_username
    leader_password     = random_string.leader_password.result
    locust_user_classes = var.locust_user_classes
    nodes_count         = var.nodes_count
    cw_config = templatefile("${path.module}/data/cloudwatch-config.json.tpl", {
      instance_name = local.locust_leader_instance_name
    })
    proxy_transparent_enabled = var.proxy_transparent_enabled
  })

  key_name = var.ec2_key_pair

  tags = {
    Name = local.locust_leader_instance_name
    Type = "locust-leader"
    DeploymentName : var.deployment_name
    DeploymentId : local.deployment_id
  }
}

resource "random_string" "leader_password" {
  length  = 24
  special = false
}
