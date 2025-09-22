resource "aws_secretsmanager_secret" "proxy_credentials" {
  count = var.proxy_credentials != "" ? 1 : 0

  name_prefix = "${var.name_prefix}-credentials-"
}

resource "aws_secretsmanager_secret_version" "proxy_credentials_version" {
  count = var.proxy_credentials != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.proxy_credentials[0].id
  secret_string = var.proxy_credentials
}

resource "aws_secretsmanager_secret" "proxy_private_key" {
  count = var.proxy_private_key != "" ? 1 : 0

  name_prefix = "${var.name_prefix}-private-key-"
}

resource "aws_secretsmanager_secret_version" "proxy_private_key_version" {
  count = var.proxy_private_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.proxy_private_key[0].id
  secret_string = var.proxy_private_key
}

resource "aws_secretsmanager_secret" "proxy_https_private_key" {
  count = var.proxy_https_key != "" ? 1 : 0

  name_prefix = "${var.name_prefix}-https-private-key-"
}

resource "aws_secretsmanager_secret_version" "proxy_https_private_key_version" {
  count = var.proxy_https_key != "" ? 1 : 0

  secret_id     = aws_secretsmanager_secret.proxy_https_private_key[0].id
  secret_string = var.proxy_https_key
}

resource "aws_secretsmanager_secret" "redis_default_connection_string" {
  count = local.redis_enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-redis-connection-default-"
}

resource "aws_secretsmanager_secret_version" "redis_default_connection_string_version" {
  count = local.redis_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.redis_default_connection_string[0].id
  secret_string = local.redis_default_connection_string
}

resource "aws_secretsmanager_secret" "redis_kivera_connection_string" {
  count = local.redis_enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-redis-connection-kivera-"
}

resource "aws_secretsmanager_secret_version" "redis_kivera_connection_string_version" {
  count = local.redis_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.redis_kivera_connection_string[0].id
  secret_string = local.redis_kivera_connection_string
}

resource "aws_iam_role" "instance_role" {
  name_prefix = "${var.name_prefix}-instance-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = "${var.name_prefix}-instance-"
  role        = aws_iam_role.instance_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_policy" "proxy_instance" {
  name_prefix = "${var.name_prefix}-default-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [local.proxy_credentials_secret_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_instance" {
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.proxy_instance.arn
}

resource "aws_iam_policy" "proxy_private_key_secret" {
  count       = var.external_ca ? 0 : 1
  name_prefix = "${var.name_prefix}-get-proxy-private-key-secret-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [local.proxy_private_key_secret_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_private_key_secret" {
  count      = var.external_ca ? 0 : 1
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.proxy_private_key_secret[0].arn
}

resource "aws_iam_policy" "proxy_https_private_key_secret" {
  count       = var.proxy_https_key != "" ? 1 : 0
  name_prefix = "${var.name_prefix}-get-proxy-https-private-key-secret-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [local.proxy_https_private_key_secret_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_https_private_key_secret" {
  count      = var.proxy_https_key != "" ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.proxy_https_private_key_secret[0].arn
}

resource "aws_iam_policy" "proxy_instance_s3" {
  count = var.proxy_local_path != "" ? 1 : 0
  name  = "${var.name_prefix}-s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:CreateMultipartUpload"
      ]
      Resource = ["arn:aws:s3:::${var.s3_bucket}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_instance_s3" {
  count      = var.proxy_local_path != "" ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.proxy_instance_s3[0].arn
}

resource "aws_iam_policy" "proxy_instance_acm" {
  count = var.external_ca ? 1 : 0
  name  = "${var.name_prefix}-acm"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "acm:*",
        "acm-pca:*"
      ]
      Resource = ["arn:aws:acm-pca:${var.region}:*:certificate-authority/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_instance_acm" {
  count      = var.external_ca ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.proxy_instance_acm[0].arn
}

resource "aws_iam_policy" "datadog_secret" {
  count       = var.enable_datadog_profiling || var.enable_datadog_tracing ? 1 : 0
  name_prefix = "${var.name_prefix}-get-datadog-secret-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [var.datadog_secret_arn]
    }]
  })

  lifecycle {
    precondition {
      condition     = length(var.datadog_secret_arn) > 0
      error_message = "datadog_secret_arn must be provided if enable_datadog_profiling or enable_datadog_tracing is true"
    }
  }
}

resource "aws_iam_role_policy_attachment" "datadog_secret" {
  count      = var.enable_datadog_profiling || var.enable_datadog_tracing ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.datadog_secret[0].arn
}

resource "aws_iam_policy" "proxy_redis_connect" {
  count = local.redis_enabled ? 1 : 0
  name  = "${var.name_prefix}-elasticache-connect"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "elasticache:Connect"
      Resource = "arn:aws:elasticache:${var.region}:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_redis_connect_attachment" {
  count      = local.redis_enabled ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.proxy_redis_connect[0].arn
}

resource "aws_iam_policy" "redis_conn_string_secret" {
  count       = local.redis_enabled ? 1 : 0
  name_prefix = "${var.name_prefix}-get-redis-connection-secret-"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [local.redis_connection_string_secret_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "redis_conn_string_secret" {
  count      = local.redis_enabled ? 1 : 0
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.redis_conn_string_secret[0].arn
}

#----------------------------
# Security Groups
#----------------------------

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

resource "aws_security_group" "redis_sg" {
  count = local.redis_enabled ? 1 : 0

  name        = "${var.name_prefix}-redis-${local.name_suffix}"
  vpc_id      = var.vpc_id
  description = "Access to the Redis cache"
}

resource "aws_vpc_security_group_ingress_rule" "redis_ingress_rule" {
  count = local.redis_enabled ? 1 : 0

  security_group_id            = aws_security_group.redis_sg[0].id
  referenced_security_group_id = aws_security_group.instance_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
}

resource "aws_vpc_security_group_egress_rule" "redis_egress_rule" {
  count = local.redis_enabled ? 1 : 0

  security_group_id = aws_security_group.redis_sg[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}
