resource "aws_route" "route_vpc_endpoint" {
  route_table_id         = var.private_subnet_rt_id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.vpc_endpoint_id
}

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "bastion_instance" {
  ami                    = data.aws_ami.latest.id
  instance_type          = "t2.micro"
  subnet_id              = var.public_subnet_id
  key_name               = var.instance_key_pair
  iam_instance_profile   = "AmazonSSMRoleForInstancesQuickSetup"
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  tags = {
    Name = "${local.stack_name}-bastion-instance"
  }
}

resource "aws_instance" "client_instance" {
  ami                    = data.aws_ami.latest.id
  instance_type          = "t2.micro"
  subnet_id              = var.private_subnet_id
  key_name               = var.instance_key_pair
  iam_instance_profile   = "AmazonSSMRoleForInstancesQuickSetup"
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
  user_data              = <<EOF
#!/bin/bash
echo ${var.proxy_public_cert} > ~/kivera/ca-cert.pem

cp ~/kivera/ca-cert.pem /etc/pki/ca-trust/source/anchors/ca-cert.pem
update-ca-trust extract

echo "
export AWS_CA_BUNDLE=\"~/kivera/ca-cert.pem\"
" > ~/kivera/setenv.sh

source ~/kivera/setenv.sh
EOF

  tags = {
    Name = "${local.stack_name}-client-instance"
  }
}

resource "aws_security_group" "instance_sg" {
  name        = "allow_ssh"
  description = "Allow ssh traffic to the instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}
