# =============================================================================
# Serverless Module — Outputs
#
# Exposes SQS queue URLs and ARNs (needed by root outputs.tf and compute module
# to populate SQS_QUEUE_LOGGING_URL in ECS task env vars), Lambda ARNs (for
# reference and potential cross-module invocation permissions), and EventBridge
# rule ARNs (for monitoring and Phase 10 CloudWatch alarms).
# =============================================================================


# =============================================================================
# SQS Queues
# =============================================================================

output "sqs_queue_logging_url" {
  description = "URL of the Logging SQS queue — injected into ECS task env var SQS_QUEUE_LOGGING_URL"
  value       = aws_sqs_queue.logging.url
}

output "sqs_queue_logging_arn" {
  description = "ARN of the Logging SQS queue"
  value       = aws_sqs_queue.logging.arn
}

output "sqs_queue_fraud_notification_url" {
  description = "URL of the Fraud Notification SQS queue — injected into Anomaly Detection Lambda env var"
  value       = aws_sqs_queue.fraud_notification.url
}

output "sqs_queue_fraud_notification_arn" {
  description = "ARN of the Fraud Notification SQS queue"
  value       = aws_sqs_queue.fraud_notification.arn
}

output "sqs_queue_fraud_notification_dlq_arn" {
  description = "ARN of the Fraud Notification dead-letter queue"
  value       = aws_sqs_queue.fraud_notification_dlq.arn
}


# =============================================================================
# Lambda Function ARNs
# =============================================================================

output "lambda_verification_arn" {
  description = "ARN of the Verification Lambda function"
  value       = aws_lambda_function.verification.arn
}

output "lambda_logging_arn" {
  description = "ARN of the Logging Lambda function"
  value       = aws_lambda_function.logging.arn
}

output "lambda_user_arn" {
  description = "ARN of the User Lambda function"
  value       = aws_lambda_function.user.arn
}

output "lambda_sftp_fetch_arn" {
  description = "ARN of the SFTP Fetch Lambda function"
  value       = aws_lambda_function.sftp_fetch.arn
}

output "lambda_anomaly_detection_arn" {
  description = "ARN of the Anomaly Detection Lambda function"
  value       = aws_lambda_function.anomaly_detection.arn
}

output "lambda_notification_arn" {
  description = "ARN of the Notification Lambda function"
  value       = aws_lambda_function.notification.arn
}


# =============================================================================
# EventBridge Rules
# =============================================================================

output "eventbridge_sftp_schedule_arn" {
  description = "ARN of the SFTP schedule EventBridge rule"
  value       = aws_cloudwatch_event_rule.sftp_schedule.arn
}

output "eventbridge_transaction_review_arn" {
  description = "ARN of the transaction-review EventBridge rule"
  value       = aws_cloudwatch_event_rule.transaction_review.arn
}


# =============================================================================
# Phase 10 — Function Names (needed by monitoring module alarm dimensions)
# =============================================================================

output "lambda_verification_function_name" {
  description = "Verification Lambda function name — used as CloudWatch alarm FunctionName dimension"
  value       = aws_lambda_function.verification.function_name
}

output "lambda_anomaly_detection_function_name" {
  description = "Anomaly Detection Lambda function name — used as CloudWatch alarm FunctionName dimension"
  value       = aws_lambda_function.anomaly_detection.function_name
}

output "lambda_notification_function_name" {
  description = "Notification Lambda function name — used as CloudWatch alarm FunctionName dimension"
  value       = aws_lambda_function.notification.function_name
}

output "lambda_logging_function_name" {
  description = "Logging Lambda function name — used as CloudWatch alarm FunctionName dimension"
  value       = aws_lambda_function.logging.function_name
}

output "sqs_fraud_notification_queue_name" {
  description = "Fraud Notification SQS queue name — used as CloudWatch alarm QueueName dimension"
  value       = aws_sqs_queue.fraud_notification.name
}

output "sqs_fraud_notification_dlq_name" {
  description = "Fraud Notification dead-letter queue name — used as CloudWatch alarm QueueName dimension"
  value       = aws_sqs_queue.fraud_notification_dlq.name
}
