output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc-networking.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc-networking.vpc_cidr
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "sg_alb_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = module.security.sg_alb_id
}

output "sg_ecs_account_primary_id" {
  description = "Security group ID for ECS Account Service primary tasks (AZ-1a)"
  value       = module.security.sg_ecs_account_primary_id
}

output "sg_ecs_account_secondary_id" {
  description = "Security group ID for ECS Account Service secondary tasks (AZ-1b)"
  value       = module.security.sg_ecs_account_secondary_id
}

output "sg_ecs_client_primary_id" {
  description = "Security group ID for ECS Client Service primary tasks (AZ-1a)"
  value       = module.security.sg_ecs_client_primary_id
}

output "sg_ecs_client_secondary_id" {
  description = "Security group ID for ECS Client Service secondary tasks (AZ-1b)"
  value       = module.security.sg_ecs_client_secondary_id
}

output "sg_rds_primary_id" {
  description = "Security group ID for Aurora RDS primary writer node"
  value       = module.security.sg_rds_primary_id
}

output "sg_elasticache_account_id" {
  description = "Security group ID for ElastiCache Redis cluster serving Account Service"
  value       = module.security.sg_elasticache_account_id
}

output "sg_elasticache_client_id" {
  description = "Security group ID for ElastiCache Redis cluster serving Client Service"
  value       = module.security.sg_elasticache_client_id
}

output "sg_secretsmanager_endpoint_id" {
  description = "Security group ID for the Secrets Manager VPC interface endpoint ENI"
  value       = module.security.sg_secretsmanager_endpoint_id
}

output "sg_ecr_endpoint_id" {
  description = "Security group ID for the ECR VPC interface endpoint ENI (shared by ecr.dkr and ecr.api)"
  value       = module.security.sg_ecr_endpoint_id
}

# =============================================================================
# VPC Endpoint Outputs
# =============================================================================

output "vpce_secretsmanager_id" {
  description = "VPC endpoint ID for Secrets Manager interface endpoint"
  value       = module.vpc-networking.secretsmanager_endpoint_id
}

output "vpce_ecr_dkr_id" {
  description = "VPC endpoint ID for ECR DKR interface endpoint (Fargate image manifest and layer pulls)"
  value       = module.vpc-networking.ecr_dkr_endpoint_id
}

output "vpce_ecr_api_id" {
  description = "VPC endpoint ID for ECR API interface endpoint (Fargate image pull authentication)"
  value       = module.vpc-networking.ecr_api_endpoint_id
}

output "vpce_s3_id" {
  description = "VPC endpoint ID for S3 gateway endpoint (ECR image layer downloads)"
  value       = module.vpc-networking.s3_endpoint_id
}

# =============================================================================
# IAM Role ARN Outputs
# =============================================================================

output "iam_role_ecs_execution_account_arn" {
  description = "ARN of the ECS task execution role for Account Service (ECR pull, Secrets Manager inject)"
  value       = module.security.iam_role_ecs_account_execution_arn
}

output "iam_role_ecs_execution_client_arn" {
  description = "ARN of the ECS task execution role for Client Service (ECR pull, Secrets Manager inject)"
  value       = module.security.iam_role_ecs_client_execution_arn
}

output "iam_role_ecs_task_account_arn" {
  description = "ARN of the ECS task role for Account Service (Accounts DynamoDB CRUD, Transactions DynamoDB read, SQS logging)"
  value       = module.security.iam_role_ecs_account_task_arn
}

output "iam_role_ecs_task_client_arn" {
  description = "ARN of the ECS task role for Client Service (SQS logging only; RDS via injected credentials)"
  value       = module.security.iam_role_ecs_client_task_arn
}

output "iam_role_lambda_verification_arn" {
  description = "ARN of the execution role for Verification Lambda (SES, S3 KYC documents, Cognito attribute update)"
  value       = module.security.iam_role_lambda_verification_arn
}

output "iam_role_lambda_logging_arn" {
  description = "ARN of the execution role for Logging Lambda (SQS Logging queue consumer, DynamoDB Logs writer)"
  value       = module.security.iam_role_lambda_logging_arn
}

output "iam_role_lambda_user_arn" {
  description = "ARN of the execution role for User Lambda (Cognito Admin API, User DynamoDB CRM metadata)"
  value       = module.security.iam_role_lambda_user_arn
}

output "iam_role_lambda_sftp_fetch_arn" {
  description = "ARN of the execution role for SFTP Fetch Lambda (Transfer Family, Secrets Manager SSH key, EventBridge)"
  value       = module.security.iam_role_lambda_sftp_fetch_arn
}

output "iam_role_lambda_anomaly_detection_arn" {
  description = "ARN of the execution role for Anomaly Detection Lambda (Transactions DynamoDB read/write, SQS Fraud Notification)"
  value       = module.security.iam_role_lambda_anomaly_detection_arn
}

output "iam_role_lambda_notification_arn" {
  description = "ARN of the execution role for Notification Lambda (SQS Fraud Notification consumer, SES agent email)"
  value       = module.security.iam_role_lambda_notification_arn
}

# =============================================================================
# KMS Key ARN Outputs
# =============================================================================

output "kms_key_rds_arn" {
  description = "ARN of the customer-managed KMS key for Aurora RDS encryption"
  value       = module.security.kms_rds_arn
}

output "kms_key_dynamodb_arn" {
  description = "ARN of the customer-managed KMS key for DynamoDB table encryption"
  value       = module.security.kms_dynamodb_arn
}

output "kms_key_elasticache_arn" {
  description = "ARN of the customer-managed KMS key for ElastiCache Redis at-rest encryption"
  value       = module.security.kms_elasticache_arn
}

output "kms_key_s3_arn" {
  description = "ARN of the customer-managed KMS key for S3 SSE-KMS encryption (SFTP bucket Phase 5; Documents + Frontend Phase 9)"
  value       = module.security.kms_s3_arn
}

output "kms_key_secrets_manager_arn" {
  description = "ARN of the customer-managed KMS key for Secrets Manager secrets (reused for Phase 6 secrets)"
  value       = module.security.kms_secrets_manager_arn
}

# =============================================================================
# RDS Aurora Outputs
# =============================================================================

output "rds_cluster_endpoint" {
  description = "Aurora cluster writer endpoint  -  used by Client Service ECS task definition in Phase 7"
  value       = module.data-layer.rds_cluster_endpoint
}

output "rds_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint  -  for read-only access (informational; application uses writer endpoint via ElastiCache)"
  value       = module.data-layer.rds_cluster_reader_endpoint
}

output "rds_cluster_port" {
  description = "Aurora cluster port (PostgreSQL 5432)"
  value       = module.data-layer.rds_cluster_port
}

output "rds_cluster_database_name" {
  description = "Name of the initial database created on the Aurora cluster (for ECS env var injection in Phase 7)"
  value       = module.data-layer.rds_cluster_database_name
}

# =============================================================================
# DynamoDB Table Outputs
# =============================================================================

output "dynamodb_table_accounts_name" {
  description = "DynamoDB Accounts table name (for ECS/Lambda env var injection in Phase 7/8)"
  value       = module.data-layer.dynamodb_table_accounts_name
}

output "dynamodb_table_logs_name" {
  description = "DynamoDB Logs table name (for Logging Lambda env var injection in Phase 8)"
  value       = module.data-layer.dynamodb_table_logs_name
}

output "dynamodb_table_users_name" {
  description = "DynamoDB Users table name (for User Lambda env var injection in Phase 8)"
  value       = module.data-layer.dynamodb_table_users_name
}

output "dynamodb_table_transactions_name" {
  description = "DynamoDB Transactions table name (for Lambda env var injection in Phase 8)"
  value       = module.data-layer.dynamodb_table_transactions_name
}

output "dynamodb_table_accounts_stream_arn" {
  description = "DynamoDB Accounts table stream ARN (for Phase 8 event trigger  -  account change events)"
  value       = module.data-layer.dynamodb_table_accounts_stream_arn
}

output "dynamodb_table_transactions_stream_arn" {
  description = "DynamoDB Transactions table stream ARN (for Phase 8 event trigger  -  transaction status change events)"
  value       = module.data-layer.dynamodb_table_transactions_stream_arn
}

# =============================================================================
# ElastiCache Redis Outputs
# =============================================================================

output "elasticache_account_primary_endpoint_address" {
  description = "Account Redis primary endpoint address (for Account Service ECS env var in Phase 7)"
  value       = module.data-layer.elasticache_account_primary_endpoint_address
}

output "elasticache_client_primary_endpoint_address" {
  description = "Client Redis primary endpoint address (for Client Service ECS env var in Phase 7)"
  value       = module.data-layer.elasticache_client_primary_endpoint_address
}

output "elasticache_account_port" {
  description = "Account Redis port (always 6379)"
  value       = module.data-layer.elasticache_account_port
}

output "elasticache_client_port" {
  description = "Client Redis port (always 6379)"
  value       = module.data-layer.elasticache_client_port
}

# =============================================================================
# S3 Bucket Outputs
# =============================================================================

output "s3_bucket_sftp_name" {
  description = "SFTP S3 bucket name (for SFTP Fetch Lambda env var injection in Phase 8)"
  value       = module.storage.s3_sftp_bucket_name
}

output "s3_bucket_sftp_arn" {
  description = "SFTP S3 bucket ARN (for future bucket policy or cross-account access)"
  value       = module.storage.s3_sftp_bucket_arn
}

# =============================================================================
# Phase 6: Authentication Outputs
# =============================================================================

output "cognito_user_pool_id" {
  description = "Cognito user pool ID  -  used for JWKS URL construction and ECS env vars"
  value       = module.auth.cognito_user_pool_id
}

output "cognito_user_pool_arn" {
  description = "Cognito user pool ARN"
  value       = module.auth.cognito_user_pool_arn
}

output "cognito_user_pool_endpoint" {
  description = "Cognito user pool endpoint"
  value       = module.auth.cognito_user_pool_endpoint
}

output "cognito_client_id" {
  description = "Cognito app client ID for frontend OAuth 2.0 configuration"
  value       = module.auth.cognito_client_id
}

output "cognito_domain" {
  description = "Cognito hosted UI full domain"
  value       = module.auth.cognito_domain
}

output "ses_identity_arn" {
  description = "SES email identity ARN for Lambda sender verification"
  value       = module.auth.ses_identity_arn
}

# =============================================================================
# Phase 7: Compute & Application Tier Outputs
# =============================================================================

output "ecs_cluster_id" {
  description = "ECS Fargate cluster ID"
  value       = module.compute.ecs_cluster_id
}

output "ecs_cluster_name" {
  description = "ECS Fargate cluster name"
  value       = module.compute.ecs_cluster_name
}

output "alb_dns_name" {
  description = "ALB DNS name  -  use for HTTP access until custom domain configured in Phase 9"
  value       = module.compute.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53 alias records (Phase 9)"
  value       = module.compute.alb_zone_id
}

output "alb_arn" {
  description = "ALB ARN for WAF association (Phase 9)"
  value       = module.compute.alb_arn
}

output "alb_listener_arn" {
  description = "HTTP listener ARN  -  upgrade to HTTPS in Phase 9"
  value       = module.compute.alb_listener_arn
}

output "ecr_repo_account_service_url" {
  description = "ECR repository URL for Account Service container images"
  value       = module.compute.ecr_repo_account_service_url
}

output "ecr_repo_client_service_url" {
  description = "ECR repository URL for Client Service container images"
  value       = module.compute.ecr_repo_client_service_url
}

output "target_group_account_arn" {
  description = "ALB target group ARN for Account Service"
  value       = module.compute.target_group_account_arn
}

output "target_group_client_arn" {
  description = "ALB target group ARN for Client Service"
  value       = module.compute.target_group_client_arn
}

# =============================================================================
# Phase 8: Event-Driven Architecture Outputs
# =============================================================================

# --- SQS Queue Outputs ---

output "sqs_queue_logging_url" {
  description = "SQS Logging queue URL  -  passed to ECS task definitions for audit event publishing"
  value       = module.serverless.sqs_queue_logging_url
}

output "sqs_queue_logging_arn" {
  description = "SQS Logging queue ARN"
  value       = module.serverless.sqs_queue_logging_arn
}

output "sqs_queue_fraud_notification_url" {
  description = "SQS Fraud Notification queue URL  -  used by Anomaly Detection Lambda to enqueue fraud alerts"
  value       = module.serverless.sqs_queue_fraud_notification_url
}

output "sqs_queue_fraud_notification_arn" {
  description = "SQS Fraud Notification queue ARN"
  value       = module.serverless.sqs_queue_fraud_notification_arn
}

output "sqs_queue_fraud_notification_dlq_arn" {
  description = "SQS Fraud Notification dead-letter queue ARN  -  holds unprocessable fraud alerts after 3 retries"
  value       = module.serverless.sqs_queue_fraud_notification_dlq_arn
}

# --- Lambda Function Outputs ---

output "lambda_verification_arn" {
  description = "Verification Lambda function ARN"
  value       = module.serverless.lambda_verification_arn
}

output "lambda_logging_arn" {
  description = "Logging Lambda function ARN"
  value       = module.serverless.lambda_logging_arn
}

output "lambda_user_arn" {
  description = "User Lambda function ARN"
  value       = module.serverless.lambda_user_arn
}

output "lambda_sftp_fetch_arn" {
  description = "SFTP Fetch Lambda function ARN"
  value       = module.serverless.lambda_sftp_fetch_arn
}

output "lambda_anomaly_detection_arn" {
  description = "Anomaly Detection Lambda function ARN"
  value       = module.serverless.lambda_anomaly_detection_arn
}

output "lambda_notification_arn" {
  description = "Notification Lambda function ARN"
  value       = module.serverless.lambda_notification_arn
}

# --- EventBridge Outputs ---

output "eventbridge_sftp_schedule_arn" {
  description = "EventBridge SFTP schedule rule ARN"
  value       = module.serverless.eventbridge_sftp_schedule_arn
}

output "eventbridge_transaction_review_arn" {
  description = "EventBridge transaction-for-review event rule ARN"
  value       = module.serverless.eventbridge_transaction_review_arn
}

# =============================================================================
# Phase 9: Frontend & CDN Outputs
# =============================================================================

# --- S3 Bucket Outputs ---

output "s3_bucket_documents_name" {
  description = "Documents S3 bucket name  -  injected into Verification Lambda as S3_BUCKET_DOCUMENTS"
  value       = module.storage.s3_documents_bucket_name
}

output "s3_bucket_documents_arn" {
  description = "Documents S3 bucket ARN"
  value       = module.storage.s3_documents_bucket_arn
}

output "s3_bucket_frontend_id" {
  description = "Frontend S3 bucket ID (name)  -  deploy compiled React SPA assets here"
  value       = module.storage.s3_frontend_bucket_id
}

output "s3_bucket_frontend_arn" {
  description = "Frontend S3 bucket ARN"
  value       = module.storage.s3_frontend_bucket_arn
}

# --- CloudFront Outputs ---

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID  -  required for cache invalidation after frontend deployments"
  value       = module.cdn.cloudfront_distribution_id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = module.cdn.cloudfront_distribution_arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (e.g. d1234.cloudfront.net)  -  primary access URL until custom domain configured"
  value       = module.cdn.cloudfront_domain_name
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN (us-east-1) for CloudFront protection"
  value       = module.cdn.waf_web_acl_arn
}

# =============================================================================
# Phase 10: Monitoring Outputs
# =============================================================================

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN  -  management event audit log for all AWS API calls"
  value       = module.monitoring.cloudtrail_arn
}

output "sns_alarms_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications  -  add subscriptions here for PagerDuty, Slack, etc."
  value       = module.monitoring.sns_alarms_topic_arn
}
