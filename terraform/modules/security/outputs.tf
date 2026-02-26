# =============================================================================
# Security Group Outputs
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

output "sg_ecr_endpoint_id" {
  description = "Security group ID for the ECR VPC interface endpoint ENI (shared by ecr.dkr and ecr.api)"
  value       = aws_security_group.ecr_endpoint.id
}

# =============================================================================
# KMS Key ARN Outputs
# =============================================================================

output "kms_rds_arn" {
  description = "ARN of the customer-managed KMS key for Aurora RDS encryption"
  value       = aws_kms_key.rds.arn
}

output "kms_dynamodb_arn" {
  description = "ARN of the customer-managed KMS key for DynamoDB table encryption"
  value       = aws_kms_key.dynamodb.arn
}

output "kms_elasticache_arn" {
  description = "ARN of the customer-managed KMS key for ElastiCache Redis at-rest encryption"
  value       = aws_kms_key.elasticache.arn
}

output "kms_s3_arn" {
  description = "ARN of the customer-managed KMS key for S3 SSE-KMS encryption"
  value       = aws_kms_key.s3.arn
}

output "kms_secrets_manager_arn" {
  description = "ARN of the customer-managed KMS key for Secrets Manager secrets"
  value       = aws_kms_key.secrets_manager.arn
}

# =============================================================================
# IAM Role ARN Outputs
# =============================================================================

output "iam_role_ecs_account_execution_arn" {
  description = "ARN of the ECS task execution role for Account Service"
  value       = aws_iam_role.ecs_execution_role_account.arn
}

output "iam_role_ecs_account_task_arn" {
  description = "ARN of the ECS task role for Account Service"
  value       = aws_iam_role.ecs_task_role_account.arn
}

output "iam_role_ecs_client_execution_arn" {
  description = "ARN of the ECS task execution role for Client Service"
  value       = aws_iam_role.ecs_execution_role_client.arn
}

output "iam_role_ecs_client_task_arn" {
  description = "ARN of the ECS task role for Client Service"
  value       = aws_iam_role.ecs_task_role_client.arn
}

output "iam_role_lambda_verification_arn" {
  description = "ARN of the execution role for Verification Lambda"
  value       = aws_iam_role.lambda_execution_role_verification.arn
}

output "iam_role_lambda_logging_arn" {
  description = "ARN of the execution role for Logging Lambda"
  value       = aws_iam_role.lambda_execution_role_logging.arn
}

output "iam_role_lambda_user_arn" {
  description = "ARN of the execution role for User Lambda"
  value       = aws_iam_role.lambda_execution_role_user.arn
}

output "iam_role_lambda_sftp_fetch_arn" {
  description = "ARN of the execution role for SFTP Fetch Lambda"
  value       = aws_iam_role.lambda_execution_role_sftp_fetch.arn
}

output "iam_role_lambda_anomaly_detection_arn" {
  description = "ARN of the execution role for Anomaly Detection Lambda"
  value       = aws_iam_role.lambda_execution_role_anomaly_detection.arn
}

output "iam_role_lambda_notification_arn" {
  description = "ARN of the execution role for Notification Lambda"
  value       = aws_iam_role.lambda_execution_role_notification.arn
}
