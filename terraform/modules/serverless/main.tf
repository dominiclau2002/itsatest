# =============================================================================
# Serverless Module
#
# Contains: SQS queues (Logging + Fraud Notification + DLQ), CloudWatch log
# groups (one per Lambda), 6 Lambda functions (Verification, Logging, User,
# SFTP Fetch, Anomaly Detection, Notification), Lambda event source mappings
# (SQS triggers), EventBridge rules + targets (SFTP schedule + transaction
# review routing), and Lambda resource-based permissions for EventBridge.
#
# Architecture: Event-driven pipeline. SFTP Fetch Lambda runs on a schedule,
# drops transaction files, emits transaction-for-review events to the default
# EventBridge bus, which routes them to Anomaly Detection Lambda. Anomaly
# Detection publishes fraud events to the Fraud Notification SQS queue, which
# triggers the Notification Lambda. The Logging Lambda drains the Logging SQS
# queue (written to by ECS services). All Lambdas run outside the VPC and
# reach AWS APIs via public endpoints.
# =============================================================================


# =============================================================================
# Module-Level Locals
#
# Recomputed from project_name + environment (same formulas as root locals.tf).
# Modules do not inherit root locals — must be defined locally.
# =============================================================================

locals {
  # Lambda function names
  lambda_verification_name = "${var.project_name}-${var.environment}-verification"
  lambda_logging_name      = "${var.project_name}-${var.environment}-logging"
  lambda_user_name         = "${var.project_name}-${var.environment}-user"
  lambda_sftp_fetch_name   = "${var.project_name}-${var.environment}-sftp-fetch"
  lambda_anomaly_name      = "${var.project_name}-${var.environment}-anomaly-detection"
  lambda_notification_name = "${var.project_name}-${var.environment}-notification"

  # CloudWatch log group names (must match /aws/lambda/<function-name> convention)
  log_group_lambda_verification = "/aws/lambda/${local.lambda_verification_name}"
  log_group_lambda_logging      = "/aws/lambda/${local.lambda_logging_name}"
  log_group_lambda_user         = "/aws/lambda/${local.lambda_user_name}"
  log_group_lambda_sftp_fetch   = "/aws/lambda/${local.lambda_sftp_fetch_name}"
  log_group_lambda_anomaly      = "/aws/lambda/${local.lambda_anomaly_name}"
  log_group_lambda_notification = "/aws/lambda/${local.lambda_notification_name}"

  # SQS queue names
  sqs_queue_logging_name            = "${var.project_name}-${var.environment}-queue-logging"
  sqs_queue_fraud_notification_name = "${var.project_name}-${var.environment}-queue-fraud-notification"
}


# =============================================================================
# Lambda Placeholder Archive
#
# Packages index.py into a zip file consumed by all 6 Lambda functions.
# Each function uses the same placeholder until real application code is
# deployed via CI/CD. source_code_hash ensures Terraform detects file changes.
# =============================================================================

# Zip the placeholder handler so all 6 Lambda functions share one deployment package
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  source_file = "${path.module}/lambda_placeholder/index.py"
  output_path = "${path.module}/lambda_placeholder/placeholder.zip"
}


# =============================================================================
# SQS Queues
#
# Two logical queues:
#   1. Logging — best-effort audit trail written by ECS services; no DLQ
#      because missed log entries are non-critical and do not need reprocessing.
#   2. Fraud Notification — critical path; DLQ captures messages that fail
#      3 processing attempts so no fraud alert is silently dropped.
# Both use SSE-SQS (AWS-managed) — messages are transient operational data,
# not long-lived PII, so AWS-managed encryption is sufficient here.
# =============================================================================

# Logging queue — receives audit log events from ECS Account and Client services
resource "aws_sqs_queue" "logging" {
  name = local.sqs_queue_logging_name

  # 4-day retention gives enough window for the Logging Lambda to drain the queue
  message_retention_seconds = 345600

  # 30 s visibility timeout = 6× the Logging Lambda's 5 s execution timeout
  # (AWS recommendation: visibility timeout >= 6× function timeout)
  visibility_timeout_seconds = 30

  # SSE-SQS (AWS-managed) — adequate for transient log payloads
  sqs_managed_sse_enabled = true

  # No DLQ — log entries are best-effort; a failed write is acceptable
  # rather than adding operational overhead for non-critical audit data

  tags = {
    Name      = local.sqs_queue_logging_name
    Component = "sqs"
  }
}

# Dead-letter queue for the Fraud Notification queue — captures messages that
# fail 3 processing attempts so no fraud alert is silently discarded
resource "aws_sqs_queue" "fraud_notification_dlq" {
  name = "${local.sqs_queue_fraud_notification_name}-dlq"

  # Match parent queue retention so poison messages are visible for the same window
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = true

  tags = {
    Name      = "${local.sqs_queue_fraud_notification_name}-dlq"
    Component = "sqs"
  }
}

# Fraud Notification queue — receives fraud events from Anomaly Detection Lambda;
# triggers the Notification Lambda to alert the assigned agent via SES email
resource "aws_sqs_queue" "fraud_notification" {
  name = local.sqs_queue_fraud_notification_name

  # 14-day retention — fraud alerts are critical; retain long enough for manual review
  message_retention_seconds = 1209600

  # 60 s visibility timeout = 6× the Notification Lambda's 10 s execution timeout
  visibility_timeout_seconds = 60

  sqs_managed_sse_enabled = true

  # After 3 failed processing attempts, route to DLQ for investigation
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fraud_notification_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name      = local.sqs_queue_fraud_notification_name
    Component = "sqs"
  }
}


# =============================================================================
# CloudWatch Log Groups — Lambda
#
# Pre-created so Lambda does not auto-create them without retention policies.
# Names follow the /aws/lambda/<function-name> convention — Lambda will
# automatically write to the matching group without additional configuration.
# =============================================================================

# Log group for Verification Lambda (account signup, email verification flows)
resource "aws_cloudwatch_log_group" "lambda_verification" {
  name              = local.log_group_lambda_verification
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name      = local.log_group_lambda_verification
    Component = "lambda-logs"
  }
}

# Log group for Logging Lambda (drains ECS audit events from the Logging SQS queue)
resource "aws_cloudwatch_log_group" "lambda_logging" {
  name              = local.log_group_lambda_logging
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name      = local.log_group_lambda_logging
    Component = "lambda-logs"
  }
}

# Log group for User Lambda (Cognito user management — create, update, disable)
resource "aws_cloudwatch_log_group" "lambda_user" {
  name              = local.log_group_lambda_user
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name      = local.log_group_lambda_user
    Component = "lambda-logs"
  }
}

# Log group for SFTP Fetch Lambda (scheduled retrieval of transaction files from S3)
resource "aws_cloudwatch_log_group" "lambda_sftp_fetch" {
  name              = local.log_group_lambda_sftp_fetch
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name      = local.log_group_lambda_sftp_fetch
    Component = "lambda-logs"
  }
}

# Log group for Anomaly Detection Lambda (transaction scoring, fraud event emission)
resource "aws_cloudwatch_log_group" "lambda_anomaly" {
  name              = local.log_group_lambda_anomaly
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name      = local.log_group_lambda_anomaly
    Component = "lambda-logs"
  }
}

# Log group for Notification Lambda (SES agent email dispatch triggered by fraud queue)
resource "aws_cloudwatch_log_group" "lambda_notification" {
  name              = local.log_group_lambda_notification
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name      = local.log_group_lambda_notification
    Component = "lambda-logs"
  }
}


# =============================================================================
# Lambda Functions
#
# All 6 functions share the same placeholder deployment package (index.py).
# publish = true creates a numbered version on each deploy, enabling future
# traffic-shifting aliases (canary deployments).
# No vpc_config — Lambdas reach AWS APIs via public endpoints; placing them
# inside the VPC would require NAT Gateway egress and add cold-start latency
# with no security benefit for these workloads.
# depends_on the matching log group ensures the group exists before Lambda
# attempts to write its first log stream, preventing a race condition.
# =============================================================================

# Verification Lambda — handles account signup confirmation and email verification;
# sends transactional emails via SES; will write documents to S3 in Phase 9
resource "aws_lambda_function" "verification" {
  function_name = local.lambda_verification_name
  role          = var.iam_role_lambda_verification_arn

  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  publish          = true

  # 30 s — verification flows involve Cognito + SES round-trips; generous timeout
  timeout     = 30
  memory_size = 256

  # Reserved concurrency caps concurrent executions to prevent runaway Lambda costs
  reserved_concurrent_executions = var.lambda_reserved_concurrency["verification"]

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      AWS_REGION           = var.aws_region
      COGNITO_USER_POOL_ID = var.cognito_user_pool_id
      S3_BUCKET_DOCUMENTS  = var.s3_documents_bucket_name
      SES_SENDER_EMAIL     = var.ses_sender_email
    }
  }

  # Ensures the log group (with retention) exists before Lambda first invocation
  depends_on = [aws_cloudwatch_log_group.lambda_verification]

  tags = {
    Name      = local.lambda_verification_name
    Component = "lambda"
  }
}

# Logging Lambda — drains the Logging SQS queue and persists audit records to
# DynamoDB Logs table; triggered via SQS event source mapping below
resource "aws_lambda_function" "logging" {
  function_name = local.lambda_logging_name
  role          = var.iam_role_lambda_logging_arn

  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  publish          = true

  # 5 s — each batch write to DynamoDB is fast; tight timeout surfaces hangs quickly
  timeout     = 5
  memory_size = 128

  reserved_concurrent_executions = var.lambda_reserved_concurrency["logging"]

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      AWS_REGION          = var.aws_region
      DYNAMODB_TABLE_LOGS = var.dynamodb_table_logs_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logging]

  tags = {
    Name      = local.lambda_logging_name
    Component = "lambda"
  }
}

# User Lambda — Cognito user management operations (create agent, update attributes,
# disable/enable accounts); invoked synchronously by the Account Service via IAM
resource "aws_lambda_function" "user" {
  function_name = local.lambda_user_name
  role          = var.iam_role_lambda_user_arn

  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  publish          = true

  # 10 s — Cognito AdminCreate/Update calls are sub-second; headroom for retries
  timeout     = 10
  memory_size = 128

  reserved_concurrent_executions = var.lambda_reserved_concurrency["user"]

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      AWS_REGION           = var.aws_region
      COGNITO_USER_POOL_ID = var.cognito_user_pool_id
      DYNAMODB_TABLE_USERS = var.dynamodb_table_users_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_user]

  tags = {
    Name      = local.lambda_user_name
    Component = "lambda"
  }
}

# SFTP Fetch Lambda — runs on the EventBridge schedule; reads new transaction files
# from the SFTP S3 bucket (transactions/ prefix), parses them, emits
# transaction-for-review events to EventBridge for downstream anomaly scoring.
# 512 MB — parsing large CSV/XLSX transaction files is memory-intensive.
# 300 s timeout (5 min) — handles large batch files with multiple records.
resource "aws_lambda_function" "sftp_fetch" {
  function_name = local.lambda_sftp_fetch_name
  role          = var.iam_role_lambda_sftp_fetch_arn

  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  publish          = true

  # 300 s — large SFTP batch files may contain thousands of transaction records
  timeout     = 300
  memory_size = 512

  # sftp_fetch = 1 minimum — this Lambda is schedule-triggered (one invocation at a time)
  reserved_concurrent_executions = var.lambda_reserved_concurrency["sftp_fetch"]

  environment {
    variables = {
      ENVIRONMENT          = var.environment
      AWS_REGION           = var.aws_region
      S3_BUCKET_SFTP       = var.s3_sftp_bucket_name
      EVENTBRIDGE_BUS_NAME = "default"
      # Secrets Manager prefix for any SFTP-related credentials (e.g. PGP keys)
      SFTP_SECRET_PREFIX = "${var.project_name}/${var.environment}/sftp"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_sftp_fetch]

  tags = {
    Name      = local.lambda_sftp_fetch_name
    Component = "lambda"
  }
}

# Anomaly Detection Lambda — receives transaction-for-review events from EventBridge,
# scores each transaction against DynamoDB Transactions history, and publishes
# fraud events to the Fraud Notification SQS queue when a threshold is exceeded
resource "aws_lambda_function" "anomaly_detection" {
  function_name = local.lambda_anomaly_name
  role          = var.iam_role_lambda_anomaly_detection_arn

  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  publish          = true

  # 30 s — scoring logic may involve multiple DynamoDB reads and SQS writes
  timeout     = 30
  memory_size = 256

  reserved_concurrent_executions = var.lambda_reserved_concurrency["anomaly_detection"]

  environment {
    variables = {
      ENVIRONMENT                      = var.environment
      AWS_REGION                       = var.aws_region
      DYNAMODB_TABLE_TRANSACTIONS      = var.dynamodb_table_transactions_name
      SQS_QUEUE_FRAUD_NOTIFICATION_URL = aws_sqs_queue.fraud_notification.url
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_anomaly]

  tags = {
    Name      = local.lambda_anomaly_name
    Component = "lambda"
  }
}

# Notification Lambda — triggered by Fraud Notification SQS queue; looks up the
# assigned agent via Accounts DynamoDB (ClientIndex GSI) then Users DynamoDB
# (GetItem by agent_id), and dispatches a fraud alert email via SES
resource "aws_lambda_function" "notification" {
  function_name = local.lambda_notification_name
  role          = var.iam_role_lambda_notification_arn

  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  publish          = true

  # 10 s — two DynamoDB reads + one SES send; tight timeout surfaces hangs quickly
  timeout     = 10
  memory_size = 128

  reserved_concurrent_executions = var.lambda_reserved_concurrency["notification"]

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      AWS_REGION              = var.aws_region
      DYNAMODB_TABLE_ACCOUNTS = var.dynamodb_table_accounts_name
      DYNAMODB_TABLE_USERS    = var.dynamodb_table_users_name
      SES_SENDER_EMAIL        = var.ses_sender_email
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_notification]

  tags = {
    Name      = local.lambda_notification_name
    Component = "lambda"
  }
}


# =============================================================================
# Lambda Event Source Mappings — SQS Triggers
#
# Connects SQS queues to Lambda functions so Lambda polls the queue and
# processes messages in batches. Managed by the Lambda service — no additional
# IAM permissions needed beyond what is already on the execution role.
# =============================================================================

# Triggers Logging Lambda when messages arrive on the Logging queue.
# batch_size = 10 — process up to 10 audit events per invocation to keep
# DynamoDB write costs predictable and invocation duration under 5 s.
resource "aws_lambda_event_source_mapping" "logging_sqs" {
  event_source_arn = aws_sqs_queue.logging.arn
  function_name    = aws_lambda_function.logging.arn
  batch_size       = 10
  enabled          = true
}

# Triggers Notification Lambda when fraud events arrive on the Fraud Notification queue.
# batch_size = 1 — each fraud alert is processed independently to prevent one
# failed SES send from blocking other alerts in the same batch.
resource "aws_lambda_event_source_mapping" "fraud_notification_sqs" {
  event_source_arn = aws_sqs_queue.fraud_notification.arn
  function_name    = aws_lambda_function.notification.arn
  batch_size       = 1
  enabled          = true
}


# =============================================================================
# EventBridge Rules
#
# Two rules on the default event bus:
#   1. sftp_schedule — time-based; fires on the configured rate/cron expression
#      to trigger the SFTP Fetch Lambda.
#   2. transaction_review — content-based; matches events emitted by SFTP Fetch
#      Lambda (source=crm.sftp-fetch, detail-type=transaction-for-review) and
#      routes them to the Anomaly Detection Lambda.
# =============================================================================

# Scheduled rule that invokes SFTP Fetch Lambda on a recurring cadence.
# Default: rate(1 hour) — override via var.sftp_schedule_expression in tfvars.
resource "aws_cloudwatch_event_rule" "sftp_schedule" {
  name                = "${var.project_name}-${var.environment}-sftp-schedule"
  description         = "Triggers SFTP Fetch Lambda on a recurring schedule to retrieve transaction files"
  schedule_expression = var.sftp_schedule_expression

  tags = {
    Name      = "${var.project_name}-${var.environment}-sftp-schedule"
    Component = "eventbridge"
  }
}

# Content-based rule that routes transaction-for-review events emitted by the
# SFTP Fetch Lambda to the Anomaly Detection Lambda for fraud scoring
resource "aws_cloudwatch_event_rule" "transaction_review" {
  name        = "${var.project_name}-${var.environment}-transaction-review"
  description = "Routes transaction-for-review events from SFTP Fetch Lambda to Anomaly Detection Lambda"

  event_pattern = jsonencode({
    source      = ["crm.sftp-fetch"]
    detail-type = ["transaction-for-review"]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-transaction-review"
    Component = "eventbridge"
  }
}


# =============================================================================
# EventBridge Targets
#
# Associates each rule with its Lambda function target. EventBridge requires
# a corresponding aws_lambda_permission (below) so it can invoke the function.
# =============================================================================

# Target: SFTP schedule rule → SFTP Fetch Lambda
resource "aws_cloudwatch_event_target" "sftp_fetch_lambda" {
  rule = aws_cloudwatch_event_rule.sftp_schedule.name
  arn  = aws_lambda_function.sftp_fetch.arn
}

# Target: transaction-review rule → Anomaly Detection Lambda
resource "aws_cloudwatch_event_target" "anomaly_detection_lambda" {
  rule = aws_cloudwatch_event_rule.transaction_review.name
  arn  = aws_lambda_function.anomaly_detection.arn
}


# =============================================================================
# Lambda Resource-Based Permissions — EventBridge
#
# Grants EventBridge (events.amazonaws.com) permission to invoke each target
# Lambda function. source_arn scopes the permission to the specific rule ARN,
# preventing other EventBridge rules from invoking these functions (least privilege).
# =============================================================================

# Allows the SFTP schedule EventBridge rule to invoke SFTP Fetch Lambda
resource "aws_lambda_permission" "sftp_fetch_eventbridge" {
  statement_id  = "AllowEventBridgeSFTPSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sftp_fetch.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sftp_schedule.arn
}

# Allows the transaction-review EventBridge rule to invoke Anomaly Detection Lambda
resource "aws_lambda_permission" "anomaly_detection_eventbridge" {
  statement_id  = "AllowEventBridgeTransactionReview"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomaly_detection.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.transaction_review.arn
}


# =============================================================================
# DynamoDB Stream Event Source Mappings — Phase 10
#
# Connects DynamoDB table streams directly to Lambda functions so Lambda
# processes record change events in near-real-time as they arrive on the stream.
# bisect_batch_on_function_error = true: when a batch fails, Lambda splits it
# in half and retries each half independently — prevents a single poison-pill
# record from blocking the entire shard indefinitely.
# =============================================================================

# Transactions stream → Logging Lambda
# Purpose: capture all transaction write events as structured audit entries in
# the DynamoDB Logs table, providing a complete immutable trail of data changes.
resource "aws_lambda_event_source_mapping" "transactions_stream" {
  event_source_arn               = var.dynamodb_stream_transactions_arn
  function_name                  = aws_lambda_function.logging.arn
  starting_position              = "LATEST"
  batch_size                     = 10
  bisect_batch_on_function_error = true
}

# Accounts stream → Anomaly Detection Lambda
# Purpose: detect anomalous account-level changes (unusual balance mutations,
# rapid state transitions) that are not captured by the EventBridge transaction
# review flow. on_failure DLQ ensures no account change event is silently lost.
resource "aws_lambda_event_source_mapping" "accounts_stream" {
  event_source_arn               = var.dynamodb_stream_accounts_arn
  function_name                  = aws_lambda_function.anomaly_detection.arn
  starting_position              = "LATEST"
  batch_size                     = 10
  bisect_batch_on_function_error = true

  # on_failure routes permanently failed batches to the Fraud Notification DLQ
  # for manual review — requires sqs:SendMessage on the DLQ in the execution role
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.fraud_notification_dlq.arn
    }
  }
}
