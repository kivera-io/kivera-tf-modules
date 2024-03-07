resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = var.vpc_id

  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = var.vpc_endpoint_id
  }

  tags = {
    Name = "${local.stack_name}-private-subnet-rt"
  }
}

resource "aws_route_table_association" "private_subnet_route_table_association" {
  subnet_id      = var.private_subnet_id
  route_table_id = aws_route_table.private_subnet_route_table.id
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
  ami           = data.aws_ami.latest.id
  instance_type = "t2.micro"
  subnet_id     = var.public_subnet_id

  tags = {
    Name = "${local.stack_name}-bastion-instance"
  }
}

resource "aws_instance" "client_instance" {
  ami           = data.aws_ami.latest.id
  instance_type = "t2.micro"
  subnet_id     = var.private_subnet_id
  user_data = <<EOF
#!/bin/bash
curl -s http://localhost:8090/pub.cert > ~/kivera/ca-cert.pem

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
