# =============================================================================
# Data Layer Module
#
# Contains: Aurora PostgreSQL cluster, DynamoDB tables, ElastiCache Redis clusters.
# All cross-module references (subnets, SGs, KMS keys) received as variables.
# =============================================================================


# =============================================================================
# Module-Level Locals
# =============================================================================
locals {
  dynamodb_table_accounts_name     = "${var.project_name}-${var.environment}-table-accounts"
  dynamodb_table_logs_name         = "${var.project_name}-${var.environment}-table-logs"
  dynamodb_table_users_name        = "${var.project_name}-${var.environment}-table-users"
  dynamodb_table_transactions_name = "${var.project_name}-${var.environment}-table-transactions"
  secrets_prefix_client            = "${var.project_name}/${var.environment}/client-service"
  secrets_prefix_account           = "${var.project_name}/${var.environment}/account-service"
}


# =============================================================================
# Aurora PostgreSQL  -  RDS
# =============================================================================

# Master Password
resource "random_password" "rds_master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "rds_master_password" {
  name        = "${local.secrets_prefix_client}/rds-master-password"
  description = "Aurora PostgreSQL master password for the CRM database. Injected into Client Service at startup."
  kms_key_id  = var.kms_secrets_manager_arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-secret-rds-master-password"
    Component = "rds"
  }
}

resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id     = aws_secretsmanager_secret.rds_master_password.id
  secret_string = random_password.rds_master.result
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Subnet group for Aurora PostgreSQL cluster  -  private-db-1 (AZ-1a) and private-db-2 (AZ-1b)"
  subnet_ids  = [var.private_db_subnet_1_id, var.private_db_subnet_2_id]

  tags = {
    Name      = "${var.project_name}-${var.environment}-db-subnet-group"
    Component = "rds"
  }
}

# RDS Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "main" {
  name        = "${var.project_name}-${var.environment}-aurora-pg15-params"
  family      = "aurora-postgresql15"
  description = "Custom Aurora PostgreSQL 15 parameters  -  enforces TLS (rds.force_ssl=1)"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora-pg15-params"
    Component = "rds"
  }
}

# Aurora Cluster
resource "aws_rds_cluster" "primary" {
  count              = var.create_rds_cluster ? 1 : 0
  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  database_name      = var.rds_database_name
  master_username    = "crmadmin"
  master_password    = random_password.rds_master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_rds_primary_id]

  storage_encrypted = true
  kms_key_id        = var.kms_rds_arn

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.main.name

  backup_retention_period   = var.rds_backup_retention_days
  preferred_backup_window   = "02:00-03:00"
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-${var.environment}-aurora-final-snapshot"

  copy_tags_to_snapshot = true # CKV_AWS_313: propagate resource tags to automated snapshots for cost allocation

  # CKV_AWS_162: IAM authentication as an additional layer alongside password auth;
  # enables fine-grained DB access control via IAM roles (not a replacement for passwords)
  iam_database_authentication_enabled = true

  # CKV_AWS_324: export PostgreSQL and upgrade logs to CloudWatch for audit and diagnostics
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection = var.rds_deletion_protection

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora"
    Component = "rds"
  }
}

# RDS Enhanced Monitoring IAM Role
data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.project_name}-${var.environment}-role-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json
  description        = "Role assumed by the RDS Enhanced Monitoring agent to publish OS metrics to CloudWatch"
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Aurora Writer Instance (ap-southeast-1a)
resource "aws_rds_cluster_instance" "writer" {
  count              = var.create_rds_cluster ? 1 : 0
  identifier         = "${var.project_name}-${var.environment}-aurora-writer"
  cluster_identifier = aws_rds_cluster.primary[0].id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.primary[0].engine
  engine_version     = aws_rds_cluster.primary[0].engine_version

  availability_zone = var.availability_zones[0]
  promotion_tier    = 0

  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_rds_arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora-writer"
    Component = "rds"
  }
}

# Aurora Reader Instance (ap-southeast-1b)
resource "aws_rds_cluster_instance" "reader" {
  count              = var.create_rds_cluster ? 1 : 0
  identifier         = "${var.project_name}-${var.environment}-aurora-reader"
  cluster_identifier = aws_rds_cluster.primary[0].id
  instance_class     = var.rds_instance_class
  engine             = aws_rds_cluster.primary[0].engine
  engine_version     = aws_rds_cluster.primary[0].engine_version

  availability_zone = var.availability_zones[1]
  promotion_tier    = 1

  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_rds_arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-aurora-reader"
    Component = "rds"
  }
}


# =============================================================================
# DynamoDB Tables
# =============================================================================

resource "aws_dynamodb_table" "accounts" {
  name             = local.dynamodb_table_accounts_name
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "account_id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_dynamodb_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  attribute {
    name = "account_id"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  global_secondary_index {
    name            = "ClientIndex"
    hash_key        = "client_id"
    projection_type = "ALL"
  }

  tags = {
    Name      = local.dynamodb_table_accounts_name
    Component = "dynamodb-accounts"
  }
}

resource "aws_dynamodb_table" "logs" {
  name         = local.dynamodb_table_logs_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "log_id"
  range_key    = "datetime"

  stream_enabled = false

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_dynamodb_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  attribute {
    name = "log_id"
    type = "S"
  }

  attribute {
    name = "datetime"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  global_secondary_index {
    name            = "ClientIndex"
    hash_key        = "client_id"
    range_key       = "datetime"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Name      = local.dynamodb_table_logs_name
    Component = "dynamodb-logs"
  }
}

resource "aws_dynamodb_table" "users" {
  name         = local.dynamodb_table_users_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  stream_enabled = false

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_dynamodb_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = {
    Name      = local.dynamodb_table_users_name
    Component = "dynamodb-users"
  }
}

resource "aws_dynamodb_table" "transactions" {
  name             = local.dynamodb_table_transactions_name
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "transaction_id"
  range_key        = "timestamp"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_dynamodb_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "client_id"
    type = "S"
  }

  global_secondary_index {
    name            = "ClientTimeIndex"
    hash_key        = "client_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  tags = {
    Name      = local.dynamodb_table_transactions_name
    Component = "dynamodb-transactions"
  }
}


# =============================================================================
# ElastiCache Redis
# =============================================================================

# Shared subnet group
resource "aws_elasticache_subnet_group" "main" {
  name        = "${var.project_name}-${var.environment}-elasticache-subnet-group"
  description = "Subnet group for ElastiCache Redis clusters  -  private-db-1 (AZ-1a) and private-db-2 (AZ-1b)"
  subnet_ids  = [var.private_db_subnet_1_id, var.private_db_subnet_2_id]

  tags = {
    Name      = "${var.project_name}-${var.environment}-elasticache-subnet-group"
    Component = "elasticache"
  }
}

# Redis AUTH Token Secrets
resource "random_password" "redis_account_auth" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "redis_account_auth" {
  name        = "${local.secrets_prefix_account}/redis-auth-token"
  description = "AUTH token for Account Service Redis cluster. Injected into Account Service ECS tasks at startup."
  kms_key_id  = var.kms_secrets_manager_arn

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
  kms_key_id  = var.kms_secrets_manager_arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-secret-redis-client-auth"
    Component = "elasticache-client"
  }
}

resource "aws_secretsmanager_secret_version" "redis_client_auth" {
  secret_id     = aws_secretsmanager_secret.redis_client_auth.id
  secret_string = random_password.redis_client_auth.result
}

# Account Redis Replication Group
# Single-node (primary only, AZ-1a). No automatic failover  -  ECS services must
# handle cache unavailability gracefully by falling back to DynamoDB directly.
resource "aws_elasticache_replication_group" "account" {
  replication_group_id = "${var.project_name}-${var.environment}-redis-account"
  description          = "Redis cache for Account Service  -  single-node primary in AZ-1a (no replica)"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.elasticache_node_type

  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  preferred_cache_cluster_azs = [var.availability_zones[0]]

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.sg_elasticache_account_id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_elasticache_arn

  transit_encryption_enabled = true
  auth_token                 = random_password.redis_account_auth.result

  snapshot_retention_limit = var.elasticache_snapshot_retention_days
  snapshot_window          = "01:00-02:00"

  apply_immediately = true

  tags = {
    Name      = "${var.project_name}-${var.environment}-redis-account"
    Component = "elasticache-account"
  }
}

# Client Redis Replication Group
# Single-node (primary only, AZ-1a). No automatic failover  -  ECS services must
# handle cache unavailability gracefully by falling back to RDS directly.
resource "aws_elasticache_replication_group" "client" {
  replication_group_id = "${var.project_name}-${var.environment}-redis-client"
  description          = "Redis cache for Client Service  -  single-node primary in AZ-1a (no replica)"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.elasticache_node_type

  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  preferred_cache_cluster_azs = [var.availability_zones[0]]

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.sg_elasticache_client_id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_elasticache_arn

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
