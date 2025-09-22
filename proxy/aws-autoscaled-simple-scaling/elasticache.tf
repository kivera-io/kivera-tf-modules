resource "aws_elasticache_subnet_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  name       = "${var.name_prefix}-subnet-group-${local.name_suffix}"
  subnet_ids = var.cache_subnet_ids

  lifecycle {
    precondition {
      condition     = length(var.cache_subnet_ids) > 0
      error_message = "cache_subnet_ids must be provided if cache_enabled is true"
    }
  }
}

resource "aws_elasticache_replication_group" "redis" {
  count = local.redis_enabled ? 1 : 0

  replication_group_id = "${var.name_prefix}-redis-${local.name_suffix}"
  description          = "Redis Cache for Kivera proxy"

  node_type            = var.cache_instance_type
  engine_version       = 7.1
  parameter_group_name = "default.redis7.cluster.on"
  # engine_version       = 7.2
  # parameter_group_name = "default.valkey7.cluster.on"
  # engine               = "valkey"

  port               = 6379
  subnet_group_name  = aws_elasticache_subnet_group.redis[0].name
  security_group_ids = [aws_security_group.redis_sg[0].id]

  multi_az_enabled           = true
  num_node_groups            = var.redis_num_node_groups
  replicas_per_node_group    = var.redis_replicas_per_node_group
  automatic_failover_enabled = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  user_group_ids             = [aws_elasticache_user_group.redis_kivera_user_group[0].user_group_id]

  apply_immediately = true
}

resource "aws_elasticache_user" "redis_kivera_default" {
  count = local.redis_enabled ? 1 : 0

  user_id       = var.cache_default_username
  user_name     = "default"
  access_string = "on -@all +ping"
  engine        = "redis"
  passwords     = [local.cache_default_pass]
}

resource "aws_elasticache_user" "redis_kivera_user" {
  count = local.redis_enabled ? 1 : 0

  user_id       = var.cache_kivera_username
  user_name     = var.cache_kivera_username
  access_string = "on ~kivera* -@all +ping +mget +get +set +mset +del +strlen +cluster|slots +cluster|shards +command"
  engine        = "redis"

  authentication_mode {
    type      = "password"
    passwords = [local.cache_kivera_pass]
  }
}

resource "aws_elasticache_user" "redis_kivera_user_iam" {
  count = local.redis_enabled ? 1 : 0

  user_id       = "${var.cache_kivera_username}-iam"
  user_name     = "${var.cache_kivera_username}-iam"
  access_string = "on ~kivera* -@all +ping +mget +get +set +mset +del +strlen +cluster|slots +cluster|shards +command"
  engine        = "redis"

  authentication_mode {
    type = "iam"
  }
}

resource "aws_elasticache_user_group" "redis_kivera_user_group" {
  count = local.redis_enabled ? 1 : 0

  engine        = "redis"
  user_group_id = var.cache_user_group
  user_ids      = [aws_elasticache_user.redis_kivera_default[0].user_id, aws_elasticache_user.redis_kivera_user[0].user_id, aws_elasticache_user.redis_kivera_user_iam[0].user_id]
}
