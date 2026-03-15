# =============================================================================
# Monitoring Module  -  Input Variables
#
# All values received from the root module. No defaults for infrastructure
# identifiers  -  they must always be explicitly supplied.
# Defaults provided only for tunable operational parameters.
# =============================================================================


# =============================================================================
# Core Identity
# =============================================================================

variable "aws_region" {
  description = "AWS region for resource placement"
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
# VPC (required for Flow Logs)
# =============================================================================

variable "vpc_id" {
  description = "VPC ID for VPC Flow Logs"
  type        = string
}


# =============================================================================
# ECS Alarm Dimensions
# =============================================================================

variable "ecs_cluster_name" {
  description = "ECS cluster name  -  CloudWatch alarm ClusterName dimension"
  type        = string
}

variable "ecs_account_service_name" {
  description = "ECS Account Service primary service name  -  CloudWatch alarm ServiceName dimension"
  type        = string
}

variable "ecs_client_service_name" {
  description = "ECS Client Service primary service name  -  CloudWatch alarm ServiceName dimension"
  type        = string
}


# =============================================================================
# ALB Alarm Dimension
# =============================================================================

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/name/abc123)  -  CloudWatch metric dimension; NOT the full ARN"
  type        = string
}


# =============================================================================
# RDS Alarm Dimension
# =============================================================================

variable "rds_cluster_identifier" {
  description = "Aurora cluster identifier  -  CloudWatch alarm DBClusterIdentifier dimension"
  type        = string
}


# =============================================================================
# DynamoDB Alarm Dimensions
# =============================================================================

variable "dynamodb_table_names" {
  description = "List of all DynamoDB table names for SystemErrors alarm aggregation"
  type        = list(string)
}


# =============================================================================
# ElastiCache Alarm Dimension
# =============================================================================

variable "elasticache_account_cluster_id" {
  description = "ElastiCache Account replication group ID  -  CloudWatch alarm ReplicationGroupId dimension"
  type        = string
}


# =============================================================================
# SQS Alarm Dimensions
# =============================================================================

variable "sqs_fraud_queue_name" {
  description = "Fraud Notification SQS queue name  -  CloudWatch alarm QueueName dimension"
  type        = string
}

variable "sqs_fraud_dlq_name" {
  description = "Fraud Notification SQS dead-letter queue name  -  CloudWatch alarm QueueName dimension"
  type        = string
}


# =============================================================================
# Lambda Alarm Dimensions
# =============================================================================

variable "lambda_verification_name" {
  description = "Verification Lambda function name  -  CloudWatch alarm FunctionName dimension"
  type        = string
}

variable "lambda_anomaly_detection_name" {
  description = "Anomaly Detection Lambda function name  -  CloudWatch alarm FunctionName dimension"
  type        = string
}

variable "lambda_notification_name" {
  description = "Notification Lambda function name  -  CloudWatch alarm FunctionName dimension"
  type        = string
}

variable "lambda_logging_name" {
  description = "Logging Lambda function name  -  CloudWatch alarm FunctionName dimension"
  type        = string
}


# =============================================================================
# Optional / Tunable Parameters (with defaults)
# =============================================================================

variable "alarm_email" {
  description = "Email address for CloudWatch alarm SNS notifications. Empty string disables email subscription."
  type        = string
  default     = ""
}

variable "cloudtrail_log_retention_days" {
  description = "Retention in days for the CloudTrail CloudWatch log group"
  type        = number
  default     = 365 # CKV_AWS_338: minimum 1 year for compliance
}

variable "kms_cloudwatch_arn" {
  description = "ARN of the CloudWatch Logs KMS key  -  encrypts CloudTrail and VPC Flow Log groups (CKV_AWS_158) and the SNS alarms topic (CKV_AWS_26)"
  type        = string
}

variable "kms_s3_arn" {
  description = "ARN of the S3 KMS key  -  used to encrypt CloudTrail S3 log files (CKV_AWS_35)"
  type        = string
}
