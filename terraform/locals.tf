locals {
  # =============================================================================
  # Resource Naming Conventions — Phase 4
  # Locks in names for all resources created in Phases 5–9.
  # These locals are used in IAM policy ARN construction so the naming contract
  # is established before any data or compute resources exist.
  # Pattern: ${project_name}-${environment}-[type]-[name]
  # =============================================================================

  # --- DynamoDB table names (created in Phase 5) ---
  dynamodb_table_accounts_name     = "${var.project_name}-${var.environment}-table-accounts"
  dynamodb_table_logs_name         = "${var.project_name}-${var.environment}-table-logs"
  dynamodb_table_users_name        = "${var.project_name}-${var.environment}-table-users"
  dynamodb_table_transactions_name = "${var.project_name}-${var.environment}-table-transactions"

  # --- SQS queue names (created in Phase 8) ---
  # sqs_queue_logging_name: receives audit events from Account and Client ECS services
  # sqs_queue_fraud_notification_name: receives flagged transactions from Anomaly Detection Lambda
  sqs_queue_logging_name            = "${var.project_name}-${var.environment}-queue-logging"
  sqs_queue_fraud_notification_name = "${var.project_name}-${var.environment}-queue-fraud-notification"

  # --- S3 bucket names (created in Phase 5 for sftp, Phase 9 for documents/frontend) ---
  # s3_bucket_sftp_name: stores raw transaction files fetched by SFTP Fetch Lambda (created Phase 5)
  s3_bucket_sftp_name      = "${var.project_name}-${var.environment}-bucket-sftp"
  s3_bucket_documents_name = "${var.project_name}-${var.environment}-bucket-documents"
  s3_bucket_frontend_name  = "${var.project_name}-${var.environment}-bucket-frontend"

  # --- ECR repository names (created in Phase 7) ---
  ecr_repo_account_service_name = "${var.project_name}-${var.environment}-account-service"
  ecr_repo_client_service_name  = "${var.project_name}-${var.environment}-client-service"

  # --- Secrets Manager path prefixes (created in Phase 6) ---
  # Wildcard suffix (/*) used in IAM policies to match all secrets under each prefix.
  # Tightened to exact secret names in Phase 6 when secrets are created.
  secrets_prefix_account = "${var.project_name}/${var.environment}/account-service"
  secrets_prefix_client  = "${var.project_name}/${var.environment}/client-service"
  secrets_prefix_sftp    = "${var.project_name}/${var.environment}/sftp"

  # --- CloudWatch log group names (created when ECS/Lambda resources are deployed) ---
  # ECS services: /ecs/[project]-[env]-[service]
  log_group_ecs_account = "/ecs/${var.project_name}-${var.environment}-account-service"
  log_group_ecs_client  = "/ecs/${var.project_name}-${var.environment}-client-service"

  # Lambda functions: /aws/lambda/[project]-[env]-[function]
  log_group_lambda_verification = "/aws/lambda/${var.project_name}-${var.environment}-verification"
  log_group_lambda_logging      = "/aws/lambda/${var.project_name}-${var.environment}-logging"
  log_group_lambda_user         = "/aws/lambda/${var.project_name}-${var.environment}-user"
  log_group_lambda_sftp_fetch   = "/aws/lambda/${var.project_name}-${var.environment}-sftp-fetch"
  log_group_lambda_anomaly      = "/aws/lambda/${var.project_name}-${var.environment}-anomaly-detection"
  log_group_lambda_notification = "/aws/lambda/${var.project_name}-${var.environment}-notification"
}
