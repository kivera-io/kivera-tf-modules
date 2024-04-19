resource "aws_security_group" "locust" {

  name = "${var.deployment_name}-locust-sg"

  description = "Locust SG"

  vpc_id = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = var.web_cidr_ingress_blocks
  }

  ingress {
    description = "HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "TCP"
    cidr_blocks = var.web_cidr_ingress_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name : "${var.deployment_name}-locust-sg"
    DeploymentName : var.deployment_name
    DeploymentId : local.deployment_id
  }
}

resource "aws_kms_key" "test_key" {}

resource "aws_kms_alias" "test_key" {
  name          = "alias/secure-key"
  target_key_id = aws_kms_key.test_key.key_id
}

resource "aws_iam_role" "locust" {
  name = "${var.deployment_name}-locust-role"

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]

  inline_policy {
    name = "${var.deployment_name}-locust-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetObject",
            "s3:PutObject",
            "s3:CreateMultipartUpload"
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:s3:::${var.s3_bucket}${var.s3_bucket_key}${local.deployment_id}/*"
          ]
        },
        {
          Action = [
            "kms:*",
          ]
          Effect = "Allow"
          Resource = [
            aws_kms_key.test_key.arn
          ]
        },
      ]
    })
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name : "${var.deployment_name}-locust-role"
    DeploymentName : var.deployment_name
    DeploymentId : local.deployment_id
  }
}

resource "aws_iam_instance_profile" "locust" {
  name = "${var.deployment_name}-locust-profile"
  role = aws_iam_role.locust.name
}
