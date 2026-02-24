# =============================================================================
# Phase 5: ElastiCache Redis Clusters
#
# Two separate Redis 7.0 replication groups — one per application service:
#   - Account Redis: caches account data for Account Service ECS tasks
#   - Client Redis:  caches client profile data for Client Service ECS tasks
#
# Both clusters:
#   - Active-passive topology: 2 nodes across 2 AZs (primary in AZ-1a, replica in AZ-1b)
#   - automatic_failover_enabled = true — automatic promotion on primary node failure
#   - multi_az_enabled = true — replica placed in the standby AZ
#   - Encryption at rest: customer-managed KMS key (aws_kms_key.elasticache)
#   - Encryption in transit: TLS enforced (transit_encryption_enabled = true)
#   - AUTH token: required by in-transit encryption; stored in Secrets Manager
#   - Snapshots: 7 days retention, window staggered before Aurora backup (02:00-03:00)
# =============================================================================


# =============================================================================
# ElastiCache Subnet Group
#
# Shared by both Account and Client Redis clusters.
# Subnets: private-db-1 (AZ-1a) and private-db-2 (AZ-1b).
# =============================================================================
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-elasticache-subnet-group"
  description = "Subnet group for ElastiCache Redis clusters — private-db-1 (AZ-1a) and private-db-2 (AZ-1b)"
  subnet_ids  = [aws_subnet.private_db_1.id, aws_subnet.private_db_2.id]

  tags = {
    Name      = "${var.project_name}-${var.environment}-elasticache-subnet-group"
    Component = "elasticache"
  }
}


# =============================================================================
# Redis AUTH Token Secrets
#
# ElastiCache AUTH tokens must be at least 16 characters, at most 128 characters,
# and may not contain spaces or @ characters.
# special = false: simplest safe option that satisfies all ElastiCache restrictions.
# Length 64 provides sufficient entropy for an auth token.
#
# Paths fall within existing execution role wildcards:
#   Account: ${secrets_prefix_account}/redis-auth-token → ecs_execution_policy_account wildcard
#   Client:  ${secrets_prefix_client}/redis-auth-token  → ecs_execution_policy_client wildcard
# =============================================================================

resource "random_password" "redis_account_auth" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "redis_account_auth" {
  name        = "${local.secrets_prefix_account}/redis-auth-token"
  description = "AUTH token for Account Service Redis cluster. Injected into Account Service ECS tasks at startup."
  kms_key_id  = aws_kms_key.secrets_manager.arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-secret-redis-account-auth"
    Component = "elasticache-account"
  }
}

resource "aws_secretsmanager_secret_version" "redis_account_auth" {
  secret_id     = aws_secretsmanager_secret.redis_account_auth.id
  secret_string = random_password.redis_account_auth.result
}

resource "random_password" "redis_client_auth" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "redis_client_auth" {
  name        = "${local.secrets_prefix_client}/redis-auth-token"
  description = "AUTH token for Client Service Redis cluster. Injected into Client Service ECS tasks at startup."
  kms_key_id  = aws_kms_key.secrets_manager.arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-secret-redis-client-auth"
    Component = "elasticache-client"
  }
}

resource "aws_secretsmanager_secret_version" "redis_client_auth" {
  secret_id     = aws_secretsmanager_secret.redis_client_auth.id
  secret_string = random_password.redis_client_auth.result
}


# =============================================================================
# Account Redis Replication Group
#
# Serves Account Service ECS tasks (both primary and secondary task SGs).
# Primary node in AZ-1a, replica in AZ-1b for AZ-local resilience.
# =============================================================================
resource "aws_elasticache_replication_group" "account" {
  replication_group_id = "${var.project_name}-${var.environment}-redis-account"
  description          = "Redis cache for Account Service — active-passive across AZ-1a and AZ-1b"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.elasticache_node_type

  # 2 nodes: 1 primary + 1 replica across 2 AZs
  num_cache_clusters = 2

  # Automatic failover promotes the replica to primary when the primary fails.
  # Requires num_cache_clusters >= 2.
  automatic_failover_enabled = true
  multi_az_enabled           = true

  # Pin primary to AZ-1a, replica to AZ-1b.
  # Order matches num_cache_clusters: first element = primary node AZ.
  preferred_cache_cluster_azs = [var.availability_zones[0], var.availability_zones[1]]

  # Network placement
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache_account.id]

  # Encryption at rest — customer-managed KMS key
  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.elasticache.arn

  # Encryption in transit — TLS enforced; AUTH token required when enabled
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_account_auth.result

  # Snapshots — 7-day retention, window staggered 1 hour before Aurora backup (02:00-03:00)
  snapshot_retention_limit = var.elasticache_snapshot_retention_days
  snapshot_window          = "01:00-02:00"

  # Apply configuration changes immediately rather than waiting for the next
  # maintenance window — reduces drift between plan and live state in dev.
  apply_immediately = true

  tags = {
    Name      = "${var.project_name}-${var.environment}-redis-account"
    Component = "elasticache-account"
  }
}


# =============================================================================
# Client Redis Replication Group
#
# Serves Client Service ECS tasks (both primary and secondary task SGs).
# Identical topology and configuration to Account Redis — separate cluster
# for service isolation (Account Service cannot reach Client's Redis cluster).
# =============================================================================
resource "aws_elasticache_replication_group" "client" {
  replication_group_id = "${var.project_name}-${var.environment}-redis-client"
  description          = "Redis cache for Client Service — active-passive across AZ-1a and AZ-1b"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.elasticache_node_type

  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  preferred_cache_cluster_azs = [var.availability_zones[0], var.availability_zones[1]]

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache_client.id]

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.elasticache.arn

  transit_encryption_enabled = true
  auth_token                 = random_password.redis_client_auth.result

  snapshot_retention_limit = var.elasticache_snapshot_retention_days
  snapshot_window          = "01:00-02:00"

  apply_immediately = true

  tags = {
    Name      = "${var.project_name}-${var.environment}-redis-client"
    Component = "elasticache-client"
  }
}
