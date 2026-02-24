output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# =============================================================================
# Security Group Outputs — Phase 3
# Exported for use by Phase 4+ resources (VPC endpoints, ECS, RDS, ElastiCache)
# =============================================================================

output "sg_alb_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "sg_ecs_account_primary_id" {
  description = "Security group ID for ECS Account Service primary tasks (AZ-1a)"
  value       = aws_security_group.ecs_account_primary.id
}

output "sg_ecs_account_secondary_id" {
  description = "Security group ID for ECS Account Service secondary tasks (AZ-1b)"
  value       = aws_security_group.ecs_account_secondary.id
}

output "sg_ecs_client_primary_id" {
  description = "Security group ID for ECS Client Service primary tasks (AZ-1a)"
  value       = aws_security_group.ecs_client_primary.id
}

output "sg_ecs_client_secondary_id" {
  description = "Security group ID for ECS Client Service secondary tasks (AZ-1b)"
  value       = aws_security_group.ecs_client_secondary.id
}

output "sg_rds_primary_id" {
  description = "Security group ID for Aurora RDS primary writer node"
  value       = aws_security_group.rds_primary.id
}

output "sg_elasticache_account_id" {
  description = "Security group ID for ElastiCache Redis cluster serving Account Service"
  value       = aws_security_group.elasticache_account.id
}

output "sg_elasticache_client_id" {
  description = "Security group ID for ElastiCache Redis cluster serving Client Service"
  value       = aws_security_group.elasticache_client.id
}

output "sg_secretsmanager_endpoint_id" {
  description = "Security group ID for the Secrets Manager VPC interface endpoint ENI"
  value       = aws_security_group.secretsmanager_endpoint.id
}

# =============================================================================
# VPC Endpoint Outputs - Phase 3b
# Exported for use by Phase 4+ resources (ECS task definitions, monitoring)
# =============================================================================

output "sg_ecr_endpoint_id" {
  description = "Security group ID for the ECR VPC interface endpoint ENI (shared by ecr.dkr and ecr.api)"
  value       = aws_security_group.ecr_endpoint.id
}

output "vpce_secretsmanager_id" {
  description = "VPC endpoint ID for Secrets Manager interface endpoint"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "vpce_ecr_dkr_id" {
  description = "VPC endpoint ID for ECR DKR interface endpoint (Fargate image manifest and layer pulls)"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpce_ecr_api_id" {
  description = "VPC endpoint ID for ECR API interface endpoint (Fargate image pull authentication)"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpce_s3_id" {
  description = "VPC endpoint ID for S3 gateway endpoint (ECR image layer downloads)"
  value       = aws_vpc_endpoint.s3.id
}

# =============================================================================
# IAM Role ARN Outputs — Phase 4
# Exported for use by Phase 7 (ECS task definitions), Phase 8 (Lambda), etc.
# =============================================================================

# --- ECS Task Execution Roles ---
# Used by the ECS agent at container startup (image pull, secret injection, log stream creation)

output "iam_role_ecs_execution_account_arn" {
  description = "ARN of the ECS task execution role for Account Service (ECR pull, Secrets Manager inject)"
  value       = aws_iam_role.ecs_execution_role_account.arn
}

output "iam_role_ecs_execution_client_arn" {
  description = "ARN of the ECS task execution role for Client Service (ECR pull, Secrets Manager inject)"
  value       = aws_iam_role.ecs_execution_role_client.arn
}

# --- ECS Task Roles ---
# Used by the running application container at runtime (DynamoDB, SQS, etc.)

output "iam_role_ecs_task_account_arn" {
  description = "ARN of the ECS task role for Account Service (Accounts DynamoDB CRUD, Transactions DynamoDB read, SQS logging)"
  value       = aws_iam_role.ecs_task_role_account.arn
}

output "iam_role_ecs_task_client_arn" {
  description = "ARN of the ECS task role for Client Service (SQS logging only; RDS via injected credentials)"
  value       = aws_iam_role.ecs_task_role_client.arn
}

# --- Lambda Execution Roles ---

output "iam_role_lambda_verification_arn" {
  description = "ARN of the execution role for Verification Lambda (SES, S3 KYC documents, Cognito attribute update)"
  value       = aws_iam_role.lambda_execution_role_verification.arn
}

output "iam_role_lambda_logging_arn" {
  description = "ARN of the execution role for Logging Lambda (SQS Logging queue consumer, DynamoDB Logs writer)"
  value       = aws_iam_role.lambda_execution_role_logging.arn
}

output "iam_role_lambda_user_arn" {
  description = "ARN of the execution role for User Lambda (Cognito Admin API, User DynamoDB CRM metadata)"
  value       = aws_iam_role.lambda_execution_role_user.arn
}

output "iam_role_lambda_sftp_fetch_arn" {
  description = "ARN of the execution role for SFTP Fetch Lambda (Transfer Family, Secrets Manager SSH key, EventBridge)"
  value       = aws_iam_role.lambda_execution_role_sftp_fetch.arn
}

output "iam_role_lambda_anomaly_detection_arn" {
  description = "ARN of the execution role for Anomaly Detection Lambda (Transactions DynamoDB read/write, SQS Fraud Notification)"
  value       = aws_iam_role.lambda_execution_role_anomaly_detection.arn
}

output "iam_role_lambda_notification_arn" {
  description = "ARN of the execution role for Notification Lambda (SQS Fraud Notification consumer, SES agent email)"
  value       = aws_iam_role.lambda_execution_role_notification.arn
}

# =============================================================================
# Phase 5 — Data Storage Outputs
# =============================================================================

# --- KMS Key ARNs ---

output "kms_key_rds_arn" {
  description = "ARN of the customer-managed KMS key for Aurora RDS encryption"
  value       = aws_kms_key.rds.arn
}

output "kms_key_dynamodb_arn" {
  description = "ARN of the customer-managed KMS key for DynamoDB table encryption"
  value       = aws_kms_key.dynamodb.arn
}

output "kms_key_elasticache_arn" {
  description = "ARN of the customer-managed KMS key for ElastiCache Redis at-rest encryption"
  value       = aws_kms_key.elasticache.arn
}

output "kms_key_s3_arn" {
  description = "ARN of the customer-managed KMS key for S3 SSE-KMS encryption (SFTP bucket Phase 5; Documents + Frontend Phase 9)"
  value       = aws_kms_key.s3.arn
}

output "kms_key_secrets_manager_arn" {
  description = "ARN of the customer-managed KMS key for Secrets Manager secrets (reused for Phase 6 secrets)"
  value       = aws_kms_key.secrets_manager.arn
}

# --- RDS Aurora ---

output "rds_cluster_endpoint" {
  description = "Aurora cluster writer endpoint — used by Client Service ECS task definition in Phase 7"
  value       = aws_rds_cluster.primary.endpoint
}

output "rds_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint — for read-only access (informational; application uses writer endpoint via ElastiCache)"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "rds_cluster_port" {
  description = "Aurora cluster port (PostgreSQL 5432)"
  value       = aws_rds_cluster.primary.port
}

output "rds_cluster_database_name" {
  description = "Name of the initial database created on the Aurora cluster (for ECS env var injection in Phase 7)"
  value       = aws_rds_cluster.primary.database_name
}

# --- DynamoDB Tables ---

output "dynamodb_table_accounts_name" {
  description = "DynamoDB Accounts table name (for ECS/Lambda env var injection in Phase 7/8)"
  value       = aws_dynamodb_table.accounts.name
}

output "dynamodb_table_logs_name" {
  description = "DynamoDB Logs table name (for Logging Lambda env var injection in Phase 8)"
  value       = aws_dynamodb_table.logs.name
}

output "dynamodb_table_users_name" {
  description = "DynamoDB Users table name (for User Lambda env var injection in Phase 8)"
  value       = aws_dynamodb_table.users.name
}

output "dynamodb_table_transactions_name" {
  description = "DynamoDB Transactions table name (for Lambda env var injection in Phase 8)"
  value       = aws_dynamodb_table.transactions.name
}

output "dynamodb_table_accounts_stream_arn" {
  description = "DynamoDB Accounts table stream ARN (for Phase 8 event trigger — account change events)"
  value       = aws_dynamodb_table.accounts.stream_arn
}

output "dynamodb_table_transactions_stream_arn" {
  description = "DynamoDB Transactions table stream ARN (for Phase 8 event trigger — transaction status change events)"
  value       = aws_dynamodb_table.transactions.stream_arn
}

# --- ElastiCache Redis ---

output "elasticache_account_primary_endpoint_address" {
  description = "Account Redis primary endpoint address (for Account Service ECS env var in Phase 7)"
  value       = aws_elasticache_replication_group.account.primary_endpoint_address
}

output "elasticache_client_primary_endpoint_address" {
  description = "Client Redis primary endpoint address (for Client Service ECS env var in Phase 7)"
  value       = aws_elasticache_replication_group.client.primary_endpoint_address
}

output "elasticache_account_port" {
  description = "Account Redis port (always 6379)"
  value       = aws_elasticache_replication_group.account.port
}

output "elasticache_client_port" {
  description = "Client Redis port (always 6379)"
  value       = aws_elasticache_replication_group.client.port
}

# --- S3 Buckets ---

output "s3_bucket_sftp_name" {
  description = "SFTP S3 bucket name (for SFTP Fetch Lambda env var injection in Phase 8)"
  value       = aws_s3_bucket.sftp.id
}

output "s3_bucket_sftp_arn" {
  description = "SFTP S3 bucket ARN (for future bucket policy or cross-account access)"
  value       = aws_s3_bucket.sftp.arn
}
