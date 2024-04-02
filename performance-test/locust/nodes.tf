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
  user_data            = data.template_file.node_user_data.rendered

  key_name = var.ec2_key_pair

  tags = {
    Name = local.locust_node_instance_name
    Type = "locust-node"
    DeploymentName : var.deployment_name
    DeploymentId : local.deployment_id
  }
}

data "template_file" "node_cw_config" {
  template = file("${path.module}/data/cloudwatch-config.json.tpl")
  vars = {
    instance_name = local.locust_node_instance_name
  }
}

data "template_file" "node_user_data" {
  template = file("${path.module}/data/node-user-data.sh.tpl")
  vars = {
    proxy_host                = var.proxy_endpoint
    proxy_transparent_enabled = var.proxy_transparent_enabled
    proxy_pub_cert            = var.proxy_pub_cert
    user_wait_min             = var.user_wait_min
    user_wait_max             = var.user_wait_max
    deployment_name           = var.deployment_name
    s3_bucket                 = var.s3_bucket
    s3_bucket_key             = var.s3_bucket_key
    deployment_id             = local.deployment_id
    leader_ip                 = aws_instance.leader.private_ip
    cw_config                 = data.template_file.node_cw_config.rendered
  }
}
