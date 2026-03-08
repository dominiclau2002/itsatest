# =============================================================================
# RDS Aurora Outputs
# =============================================================================

output "rds_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.primary.endpoint
}

output "rds_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "rds_cluster_port" {
  description = "Aurora cluster port (PostgreSQL 5432)"
  value       = aws_rds_cluster.primary.port
}

output "rds_cluster_database_name" {
  description = "Name of the initial database created on the Aurora cluster"
  value       = aws_rds_cluster.primary.database_name
}

# =============================================================================
# DynamoDB Outputs
# =============================================================================

output "dynamodb_table_accounts_name" {
  description = "DynamoDB Accounts table name"
  value       = aws_dynamodb_table.accounts.name
}

output "dynamodb_table_logs_name" {
  description = "DynamoDB Logs table name"
  value       = aws_dynamodb_table.logs.name
}

output "dynamodb_table_users_name" {
  description = "DynamoDB Users table name"
  value       = aws_dynamodb_table.users.name
}

output "dynamodb_table_transactions_name" {
  description = "DynamoDB Transactions table name"
  value       = aws_dynamodb_table.transactions.name
}

output "dynamodb_table_accounts_stream_arn" {
  description = "DynamoDB Accounts table stream ARN"
  value       = aws_dynamodb_table.accounts.stream_arn
}

output "dynamodb_table_transactions_stream_arn" {
  description = "DynamoDB Transactions table stream ARN"
  value       = aws_dynamodb_table.transactions.stream_arn
}

# =============================================================================
# ElastiCache Outputs
# =============================================================================

output "elasticache_account_primary_endpoint_address" {
  description = "Account Redis primary endpoint address"
  value       = aws_elasticache_replication_group.account.primary_endpoint_address
}

output "elasticache_account_port" {
  description = "Account Redis port (always 6379)"
  value       = aws_elasticache_replication_group.account.port
}

output "elasticache_client_primary_endpoint_address" {
  description = "Client Redis primary endpoint address"
  value       = aws_elasticache_replication_group.client.primary_endpoint_address
}

output "elasticache_client_port" {
  description = "Client Redis port (always 6379)"
  value       = aws_elasticache_replication_group.client.port
}

# =============================================================================
# Secrets Manager ARN Outputs (for ECS task definition secret injection)
# =============================================================================

output "secret_rds_master_password_arn" {
  description = "Secrets Manager ARN for RDS master password — injected into Client Service ECS task"
  value       = aws_secretsmanager_secret.rds_master_password.arn
}

output "secret_redis_account_auth_arn" {
  description = "Secrets Manager ARN for Account Redis AUTH token — injected into Account Service ECS task"
  value       = aws_secretsmanager_secret.redis_account_auth.arn
}

output "secret_redis_client_auth_arn" {
  description = "Secrets Manager ARN for Client Redis AUTH token — injected into Client Service ECS task"
  value       = aws_secretsmanager_secret.redis_client_auth.arn
}

# =============================================================================
# RDS Cluster Username Output
# =============================================================================

output "rds_cluster_master_username" {
  description = "Aurora master username — single source of truth for ECS task definition env var"
  value       = aws_rds_cluster.primary.master_username
}

output "dynamodb_table_logs_arn" {
  description = "DynamoDB Logs table ARN — exported for reference; security module constructs ARN locally via naming convention to avoid circular dependency"
  value       = aws_dynamodb_table.logs.arn
}


# =============================================================================
# Phase 10 — Monitoring Module Inputs
# =============================================================================

output "rds_cluster_identifier" {
  description = "Aurora cluster identifier — used as CloudWatch alarm DBClusterIdentifier dimension"
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "elasticache_account_cluster_id" {
  description = "ElastiCache Account replication group ID — used as CloudWatch alarm ReplicationGroupId dimension"
  value       = aws_elasticache_replication_group.account.id
}
