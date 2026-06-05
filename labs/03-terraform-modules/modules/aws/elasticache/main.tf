# ============================================================
# ElastiCache Module — Redis/Memcached Replication Group
# with Encryption, Auth, Subnet Group, and Parameter Group
# Author: Jenella Awo
# ============================================================

locals {
  cluster_name = "${var.project_name}-${var.cluster_name}"
  is_redis     = var.engine == "redis"
}

# ----------------------------------------------
# Subnet Group
# ----------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.cluster_name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-subnet-group"
  })
}

# ----------------------------------------------
# Parameter Group
# ----------------------------------------------
resource "aws_elasticache_parameter_group" "this" {
  name   = "${local.cluster_name}-params"
  family = var.parameter_group_family

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-params"
  })
}

# ----------------------------------------------
# Redis Replication Group
# ----------------------------------------------
resource "aws_elasticache_replication_group" "redis" {
  count = local.is_redis ? 1 : 0

  replication_group_id = local.cluster_name
  description          = "${var.project_name} Redis replication group"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = var.security_group_ids

  # Cluster mode configuration
  num_node_groups         = var.num_node_groups
  replicas_per_node_group = var.replicas_per_node_group

  # High availability
  automatic_failover_enabled = var.num_node_groups > 1 || var.replicas_per_node_group > 0 ? true : false
  multi_az_enabled           = var.replicas_per_node_group > 0 ? true : false

  # Encryption
  at_rest_encryption_enabled = var.at_rest_encryption
  transit_encryption_enabled = var.transit_encryption
  auth_token                 = var.transit_encryption ? var.auth_token : null

  # Maintenance
  snapshot_retention_limit = 7
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:07:00"
  auto_minor_version_upgrade = true

  tags = merge(var.tags, {
    Name = local.cluster_name
  })
}

# ----------------------------------------------
# Memcached Cluster
# ----------------------------------------------
resource "aws_elasticache_cluster" "memcached" {
  count = local.is_redis ? 0 : 1

  cluster_id           = local.cluster_name
  engine               = "memcached"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  port                 = 11211
  parameter_group_name = aws_elasticache_parameter_group.this.name
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = var.security_group_ids

  az_mode = var.num_cache_nodes > 1 ? "cross-az" : "single-az"

  maintenance_window = "sun:05:00-sun:07:00"

  tags = merge(var.tags, {
    Name = local.cluster_name
  })
}
