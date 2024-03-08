resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  instance_tenancy     = "default"

  tags = {
    Name = "${local.stack_name}-vpc"
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.stack_name}-igw"
  }
}

resource "aws_eip" "eip" {
  domain = "vpc"

  tags = {
    Name = "${local.stack_name}-eip"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "${local.stack_name}-ngw"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = var.availability_zone1
  cidr_block              = var.egress_subnet_cidr
  map_public_ip_on_launch = "true"

  tags = {
    Name = "${local.stack_name}-public-subnet"
  }
}

resource "aws_subnet" "proxy_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = var.availability_zone1
  cidr_block              = var.inspection_subnet_cidr
  map_public_ip_on_launch = "false"

  tags = {
    Name = "${local.stack_name}-proxy-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = var.availability_zone1
  cidr_block              = var.private_subnet_cidr
  map_public_ip_on_launch = "false"

  tags = {
    Name = "${local.stack_name}-private-subnet"
  }
}

resource "aws_route_table" "public_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "${local.stack_name}-public-subnet-rt"
  }
}

resource "aws_route_table_association" "public_subnet_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_subnet_route_table.id
}

resource "aws_route_table" "proxy_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "${local.stack_name}-proxy-subnet-rt"
  }
}

resource "aws_route_table_association" "proxy_subnet_route_table_association" {
  subnet_id      = aws_subnet.proxy_subnet.id
  route_table_id = aws_route_table.proxy_subnet_route_table.id
}

resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.stack_name}-private-subnet-rt"
  }
}

resource "aws_route_table_association" "private_subnet_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_subnet_route_table.id
}

resource "aws_iam_role" "vpce_service_lambda_execution_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com"
          ]
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  })
  path = "/"
  inline_policy {
    name = "${local.stack_name}-root"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:*:*:*"
        },
        {
          Effect = "Allow"
          Action = [
            "ec2:DescribeVpcEndpointServiceConfigurations",
            "ec2:DescribeVpcEndpointServicePermissions",
            "ec2:DescribeVpcEndpointServices"
          ]
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    Name = "${local.stack_name}-iam-lambda"
  }
}

resource "aws_cloudwatch_log_group" "vpc_service_log_group" {
  name              = "${local.stack_name}-vpc-service-log-group"
  retention_in_days = 1
}

resource "aws_security_group" "glb_sg" {
  vpc_id      = aws_vpc.vpc.id
  name        = "${local.stack_name}-glb-sg"
  description = "Access to application instance: allow TCP, UDP and ICMP from appropriate location. Allow all traffic from VPC CIDR."

  tags = {
    Name = "${local.stack_name}-glb-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "glb_ingress_rule_1" {
  security_group_id = aws_security_group.glb_sg.id
  cidr_ipv4         = var.access_location
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
}

resource "aws_vpc_security_group_ingress_rule" "glb_ingress_rule_2" {
  security_group_id = aws_security_group.glb_sg.id
  cidr_ipv4         = var.access_location
  ip_protocol       = "ICMP"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_ingress_rule" "glb_ingress_rule_3" {
  security_group_id = aws_security_group.glb_sg.id
  cidr_ipv4         = var.access_location
  ip_protocol       = "udp"
  from_port         = 0
  to_port           = 65535
}

resource "aws_vpc_security_group_ingress_rule" "glb_ingress_rule_4" {
  security_group_id = aws_security_group.glb_sg.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  from_port         = -1
  to_port           = -1
}

resource "aws_vpc_security_group_egress_rule" "glb_egress_rule" {
  security_group_id = aws_security_group.glb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  from_port         = -1
  to_port           = -1
}
