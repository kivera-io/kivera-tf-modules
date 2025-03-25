resource "aws_instance" "nodes" {

  depends_on = [aws_s3_object.tests]

  count = var.nodes_count

  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = var.nodes_instance_type

  associate_public_ip_address = var.nodes_associate_public_ip_address
  monitoring                  = var.nodes_monitoring

  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.locust.id]

  iam_instance_profile = aws_iam_instance_profile.locust.name
  user_data = templatefile("${path.module}/data/node-user-data.sh.tpl", {
    proxy_host                = var.proxy_endpoint
    proxy_transparent_enabled = var.proxy_transparent_enabled
    proxy_public_cert         = var.proxy_public_cert
    user_wait_min             = var.user_wait_min
    user_wait_max             = var.user_wait_max
    locust_user_classes       = var.locust_user_classes
    deployment_name           = var.deployment_name
    s3_bucket                 = var.s3_bucket
    s3_bucket_key             = var.s3_bucket_key
    max_client_reuse          = var.max_client_reuse
    test_timeout              = var.test_timeout
    deployment_id             = local.deployment_id
    locust_user_classes       = var.locust_user_classes
    leader_ip                 = aws_instance.leader.private_ip
    cw_config = templatefile("${path.module}/data/cloudwatch-config.json.tpl", {
      instance_name = local.locust_node_instance_name
    })
  })

  key_name = var.ec2_key_pair

  tags = {
    Name = local.locust_node_instance_name
    Type = "locust-node"
    DeploymentName : var.deployment_name
    DeploymentId : local.deployment_id
  }
}
