# =============================================================================
# Serverless Module  -  Input Variables
#
# All values received from the root module. No defaults for infrastructure
# identifiers  -  they must always be explicitly supplied.
# Defaults provided only for tunable operational parameters.
# =============================================================================


# =============================================================================
# Core Identity
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}


# =============================================================================
# IAM Role ARNs (from security module)
# =============================================================================

variable "iam_role_lambda_verification_arn" {
  description = "IAM role ARN for Verification Lambda"
  type        = string
}

variable "iam_role_lambda_logging_arn" {
  description = "IAM role ARN for Logging Lambda"
  type        = string
}

variable "iam_role_lambda_user_arn" {
  description = "IAM role ARN for User Lambda"
  type        = string
}

variable "iam_role_lambda_sftp_fetch_arn" {
  description = "IAM role ARN for SFTP Fetch Lambda"
  type        = string
}

variable "iam_role_lambda_anomaly_detection_arn" {
  description = "IAM role ARN for Anomaly Detection Lambda"
  type        = string
}

variable "iam_role_lambda_notification_arn" {
  description = "IAM role ARN for Notification Lambda"
  type        = string
}


# =============================================================================
# Data Layer References
# =============================================================================

variable "dynamodb_table_accounts_name" {
  description = "DynamoDB Accounts table name"
  type        = string
}

variable "dynamodb_table_logs_name" {
  description = "DynamoDB Logs table name"
  type        = string
}

variable "dynamodb_table_users_name" {
  description = "DynamoDB Users table name"
  type        = string
}

variable "dynamodb_table_transactions_name" {
  description = "DynamoDB Transactions table name"
  type        = string
}


# =============================================================================
# Storage
# =============================================================================

variable "s3_sftp_bucket_name" {
  description = "SFTP S3 bucket name for SFTP Fetch Lambda"
  type        = string
}


# =============================================================================
# Auth
# =============================================================================

variable "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  type        = string
}

variable "ses_sender_email" {
  description = "SES verified sender email for Verification and Notification Lambdas"
  type        = string
}


# =============================================================================
# Tunable Parameters (with defaults)
# =============================================================================

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention in days for Lambda functions"
  type        = number
  default     = 365 # CKV_AWS_338: minimum 1 year for compliance
}

variable "kms_cloudwatch_arn" {
  description = "ARN of the CloudWatch Logs KMS key  -  used to encrypt all Lambda log groups at rest (CKV_AWS_158)"
  type        = string
}

variable "sftp_schedule_expression" {
  description = "EventBridge schedule expression for SFTP fetch (e.g. rate(1 hour))"
  type        = string
  default     = "rate(1 hour)"
}

# =============================================================================
# Phase 9  -  Documents S3 Bucket
# =============================================================================

variable "s3_documents_bucket_name" {
  description = "Documents S3 bucket name  -  injected into Verification Lambda as S3_BUCKET_DOCUMENTS env var (was empty placeholder in Phase 8)"
  type        = string
}


# =============================================================================
# Phase 10  -  DynamoDB Stream ARNs
# =============================================================================

variable "dynamodb_stream_transactions_arn" {
  description = "DynamoDB Transactions table stream ARN  -  used by Transactions→Logging Lambda event source mapping"
  type        = string
}

variable "dynamodb_stream_accounts_arn" {
  description = "DynamoDB Accounts table stream ARN  -  used by Accounts→Anomaly Detection Lambda event source mapping"
  type        = string
}


# =============================================================================
# Phase 10  -  Lambda Reserved Concurrency
# =============================================================================

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent execution limits per Lambda function. Setting to 0 disables the function entirely  -  never set sftp_fetch to 0."
  type        = map(number)
  default = {
    verification      = -1
    logging           = -1
    user              = -1
    sftp_fetch        = -1
    anomaly_detection = -1
    notification      = -1
  }
}
