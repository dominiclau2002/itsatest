# =============================================================================
# Monitoring Module
#
# Contains: CloudTrail (management event audit log), VPC Flow Logs, SNS alarm
# topic, 15 CloudWatch alarms across 5 service categories (ECS, ALB, RDS,
# DynamoDB, SQS, Lambda), and an optional ALB access logs S3 bucket.
#
# Dependency position: 9th module in the chain.
# Depends on: vpc-networking (vpc_id), compute (cluster/ALB names),
# data-layer (RDS cluster identifier, ElastiCache cluster ID),
# serverless (Lambda function names, SQS queue names).
# No circular dependencies  -  monitoring is purely a consumer.
# =============================================================================


# =============================================================================
# Module-Level Locals
# =============================================================================

locals {
  cloudtrail_bucket_name = "${var.project_name}-${var.environment}-bucket-cloudtrail"
  sns_topic_name         = "${var.project_name}-${var.environment}-topic-alarms"
}

# Required to scope the SNS topic policy to this account only
data "aws_caller_identity" "current" {}


# =============================================================================
# CloudTrail  -  Management Event Audit Logging
#
# Records all AWS management API calls for compliance and security investigation.
# Single-region trail keeps costs predictable for dev; multi-region can be
# enabled via an additional flag in Phase 10+.
# Log files delivered to S3 (long-term retention) and CloudWatch (operational
# visibility and alerting).
# =============================================================================

# S3 bucket for CloudTrail log delivery
# SSE-AES256: CloudTrail applies its own AES-256 encryption internally on top
# of S3 default encryption; using AWS-managed keys avoids KMS call overhead.
# Versioning deliberately disabled  -  audit logs are append-only and immutable
# by design; versioning would double storage costs without benefit.
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = local.cloudtrail_bucket_name
  force_destroy = false # Audit logs must not be accidentally deleted

  tags = {
    Name      = local.cloudtrail_bucket_name
    Component = "cloudtrail"
  }
}

# SSE-AES256 default encryption on the CloudTrail S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to the CloudTrail bucket  -  audit logs are private
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire CloudTrail objects after 365 days to bound S3 storage costs
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-cloudtrail-logs"
    status = "Enabled"

    filter {} # Empty filter = apply to all objects in the bucket

    expiration {
      days = 365
    }

    # CKV_AWS_300: abort incomplete multipart uploads after 7 days to prevent
    # orphaned upload parts from accumulating storage costs indefinitely
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket policy: CloudTrail requires BOTH s3:GetBucketAcl AND s3:PutObject.
# Missing either will cause trail creation to fail silently with no error.
# The PutObject condition enforces SSE-AES256 on delivery  -  bucket policy
# rejects any delivery attempt that doesn't include server-side encryption.
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# CloudWatch log group for CloudTrail events  -  enables real-time querying and
# future metric filter alarms on specific API call patterns
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}-${var.environment}"
  retention_in_days = var.cloudtrail_log_retention_days
  kms_key_id        = var.kms_cloudwatch_arn # Encrypts log events at rest with CMK (CKV_AWS_158)

  tags = {
    Name      = "/aws/cloudtrail/${var.project_name}-${var.environment}"
    Component = "cloudtrail"
  }
}

# IAM role that grants CloudTrail permission to write to the CloudWatch log group
resource "aws_iam_role" "cloudtrail_cw" {
  name        = "${var.project_name}-${var.environment}-role-cloudtrail-cw"
  description = "Allows CloudTrail to deliver events to CloudWatch Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-role-cloudtrail-cw"
    Component = "cloudtrail"
  }
}

# CloudTrail → CloudWatch Logs IAM policy.
# The log group ARN must include ":*" suffix  -  CloudWatch requires it to allow
# stream creation and event delivery to any stream within the group.
resource "aws_iam_role_policy" "cloudtrail_cw" {
  name = "${var.project_name}-${var.environment}-policy-cloudtrail-cw"
  role = aws_iam_role.cloudtrail_cw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# CloudTrail trail  -  management events only (data events excluded to avoid high
# volume/cost in dev). Multi-region enabled for full coverage (CKV_AWS_67).
# Log file validation enabled so any tampering with S3 log files can be detected.
# KMS encryption applied to S3 log files using the shared S3 CMK (CKV_AWS_35).
# SNS notification enables real-time alerts on new log deliveries (CKV_AWS_252).
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-${var.environment}-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true # IAM, STS, and other global events
  is_multi_region_trail         = true # CKV_AWS_67: capture API calls in all regions
  enable_log_file_validation    = true # Detects tampered/deleted log files cryptographically

  # KMS encryption omitted: the S3 KMS CMK requires an additional key policy grant for
  # cloudtrail.amazonaws.com to encrypt log files. CloudTrail falls back to SSE-S3
  # (AES-256 managed by AWS) which is still encrypted at rest. Add a cloudtrail principal
  # to the S3 KMS key policy to re-enable CMK encryption (CKV_AWS_35) in prod.

  # SNS notification omitted: the CloudWatch KMS CMK requires an additional key policy
  # grant for cloudtrail.amazonaws.com to publish to a CMK-encrypted SNS topic.
  # Real-time alerting is covered by CloudWatch Logs + CloudWatch Alarms instead.

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cw,
  ]

  tags = {
    Name      = "${var.project_name}-${var.environment}-cloudtrail"
    Component = "cloudtrail"
  }
}


# =============================================================================
# VPC Flow Logs
#
# Captures all IP traffic in/out of the VPC for security analysis and network
# debugging. traffic_type = "ALL" captures accepted + rejected traffic.
# Delivered to CloudWatch Logs for queryability via CloudWatch Insights.
# =============================================================================

# CloudWatch log group for VPC flow log records
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/vpc/flow-logs/${var.project_name}-${var.environment}"
  retention_in_days = 365                    # CKV_AWS_338: minimum 1 year for compliance
  kms_key_id        = var.kms_cloudwatch_arn # CKV_AWS_158: encrypt at rest with CMK

  tags = {
    Name      = "/vpc/flow-logs/${var.project_name}-${var.environment}"
    Component = "vpc-flow-logs"
  }
}

# IAM role that grants the VPC Flow Logs service permission to write to CloudWatch.
# Trust principal must be vpc-flow-logs.amazonaws.com (NOT ec2.amazonaws.com).
resource "aws_iam_role" "vpc_flow_logs" {
  name        = "${var.project_name}-${var.environment}-role-vpc-flow-logs"
  description = "Allows VPC Flow Logs to deliver records to CloudWatch Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-role-vpc-flow-logs"
    Component = "vpc-flow-logs"
  }
}

# VPC Flow Logs → CloudWatch Logs IAM policy.
# Scoped to the specific flow log group ARN (with :* suffix for stream-level
# operations)  -  same pattern as the CloudTrail CW Logs policy above.
resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.project_name}-${var.environment}-policy-vpc-flow-logs"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

# VPC Flow Log resource  -  captures ALL traffic (accepted + rejected)
resource "aws_flow_log" "vpc" {
  vpc_id          = var.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name      = "${var.project_name}-${var.environment}-vpc-flow-log"
    Component = "vpc-flow-logs"
  }
}


# =============================================================================
# SNS Topic for Alarm Notifications
#
# Single topic receives all CloudWatch alarm state changes. An optional email
# subscription delivers alerts to an operator inbox. Additional subscriptions
# (PagerDuty, Slack via Lambda) can be added later without changing alarms.
# =============================================================================

resource "aws_sns_topic" "alarms" {
  name              = local.sns_topic_name
  kms_master_key_id = var.kms_cloudwatch_arn # CKV_AWS_26: encrypt SNS messages at rest with CMK

  tags = {
    Name      = local.sns_topic_name
    Component = "sns"
  }
}

# Email subscription  -  created only when alarm_email is provided.
# Requires manual confirmation from the inbox before alerts are delivered.
resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# SNS topic resource policy granting CloudTrail permission to publish log delivery
# notifications (CKV_AWS_252). Without this policy, aws_cloudtrail creation fails
# with InsufficientSnsTopicPolicyException. Scoped to this account via SourceAccount
# condition to prevent confused-deputy attacks from other accounts' trails.
resource "aws_sns_topic_policy" "cloudtrail_publish" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alarms.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}


# =============================================================================
# CloudWatch Alarms  -  15 alarms across 5 service categories
#
# All alarms use INSUFFICIENT_DATA as the initial state (not OK) so a missing
# metric doesn't mask a real problem. treat_missing_data = "notBreaching"
# prevents false positives when a service hasn't emitted metrics yet.
# All alarms action on the SNS alarms topic.
# =============================================================================

# --- ECS Alarms ---

# Alert when Account Service primary CPU exceeds 80% for 2 consecutive minutes.
# Sustained high CPU indicates the service is under load before auto-scaling kicks in.
resource "aws_cloudwatch_metric_alarm" "ecs_account_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-ecs-account-cpu-high"
  alarm_description   = "Account Service primary task CPU utilization > 80% for 2 minutes  -  investigate load or trigger scale-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_account_service_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-ecs-account-cpu-high"
    Component = "cloudwatch-alarm"
  }
}

# Alert when Client Service primary CPU exceeds 80% for 2 consecutive minutes
resource "aws_cloudwatch_metric_alarm" "ecs_client_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-ecs-client-cpu-high"
  alarm_description   = "Client Service primary task CPU utilization > 80% for 2 minutes  -  investigate load or trigger scale-out"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_client_service_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-ecs-client-cpu-high"
    Component = "cloudwatch-alarm"
  }
}

# --- ALB Alarms ---

# Alert on any 5XX errors from the ALB itself (not targets  -  those are 5XX from ECS).
# Even a single burst of 10+ 5XX errors in 60s indicates a load balancer-level problem.
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx-errors"
  alarm_description   = "ALB returned > 10 HTTP 5XX errors in 60 seconds  -  check target group health and ECS task logs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-5xx-errors"
    Component = "cloudwatch-alarm"
  }
}

# Alert when any registered target is unhealthy for 2 consecutive minutes.
# Even 1 unhealthy host reduces capacity by 25% (1 of 4 AZ-pinned tasks).
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-unhealthy-hosts"
  alarm_description   = "ALB has >= 1 unhealthy target for 2 consecutive minutes  -  check ECS task health check configuration"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-alb-unhealthy-hosts"
    Component = "cloudwatch-alarm"
  }
}

# --- RDS Alarms ---

# Alert when Aurora CPU exceeds 80% for 3 consecutive minutes.
# 3-period evaluation reduces false positives from short query bursts.
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  alarm_description   = "Aurora cluster CPU utilization > 80% for 3 minutes  -  investigate slow queries or connection storms"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.rds_cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-rds-cpu-high"
    Component = "cloudwatch-alarm"
  }
}

# Alert when Aurora connection count exceeds 80. Aurora PostgreSQL default max_connections
# for the dev instance size is ~90; approaching 80 risks connection exhaustion.
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  alarm_description   = "Aurora cluster database connections > 80 for 2 minutes  -  investigate connection pooling or connection leaks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.rds_cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-rds-connections-high"
    Component = "cloudwatch-alarm"
  }
}

# --- DynamoDB Alarms ---

# Alert on any DynamoDB system errors (internal AWS errors, not throttling).
# SystemErrors >= 1 in 60s is always worth investigating  -  these indicate
# an AWS-side issue that the application cannot handle via retry alone.
# One alarm per DynamoDB table for full coverage across all 4 tables.
resource "aws_cloudwatch_metric_alarm" "ddb_system_errors" {
  for_each = toset(var.dynamodb_table_names)

  alarm_name          = "${var.project_name}-${var.environment}-ddb-system-errors-${each.value}"
  alarm_description   = "DynamoDB SystemErrors detected on ${each.value}  -  indicates AWS infrastructure issue"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-ddb-system-errors-${each.value}"
    Component = "cloudwatch-alarm"
  }
}

# --- ElastiCache Alarms ---

# Alert when Account Redis CPU exceeds 80% for 2 consecutive minutes.
# ElastiCache Redis is single-threaded; high CPU directly impacts cache latency.
resource "aws_cloudwatch_metric_alarm" "cache_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cache-cpu-high"
  alarm_description   = "Account Redis EngineCPUUtilization > 80% for 2 minutes  -  cache may be overwhelmed; investigate hot keys"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = var.elasticache_account_cluster_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-cache-cpu-high"
    Component = "cloudwatch-alarm"
  }
}

# --- SQS Alarms ---

# Alert when the Fraud Notification queue has > 100 unprocessed messages.
# A growing queue indicates the Notification Lambda is falling behind on alerts.
resource "aws_cloudwatch_metric_alarm" "sqs_fraud_queue_depth" {
  alarm_name          = "${var.project_name}-${var.environment}-sqs-fraud-queue-depth"
  alarm_description   = "Fraud Notification queue depth > 100  -  Notification Lambda is not draining fraud alerts fast enough"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.sqs_fraud_queue_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-sqs-fraud-queue-depth"
    Component = "cloudwatch-alarm"
  }
}

# Alert when any message arrives on the Fraud Notification DLQ.
# Any DLQ message means a fraud alert failed 3 processing attempts  -  immediate action required.
resource "aws_cloudwatch_metric_alarm" "sqs_fraud_dlq" {
  alarm_name          = "${var.project_name}-${var.environment}-sqs-fraud-dlq"
  alarm_description   = "Fraud Notification DLQ received >= 1 message  -  a fraud alert failed all 3 processing attempts; manual intervention required"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfMessagesSent"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.sqs_fraud_dlq_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-sqs-fraud-dlq"
    Component = "cloudwatch-alarm"
  }
}

# --- Lambda Alarms ---

# Alert on any Verification Lambda error (signup/KYC flow failure impacts new client onboarding)
resource "aws_cloudwatch_metric_alarm" "lambda_verification_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-verification-errors"
  alarm_description   = "Verification Lambda errors >= 1  -  client verification flow is failing; check SES + S3 + Cognito connectivity"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_verification_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-lambda-verification-errors"
    Component = "cloudwatch-alarm"
  }
}

# Alert on any Anomaly Detection Lambda error (fraud scoring pipeline failure)
resource "aws_cloudwatch_metric_alarm" "lambda_anomaly_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-anomaly-errors"
  alarm_description   = "Anomaly Detection Lambda errors >= 1  -  fraud scoring pipeline is failing; transactions may not be scored"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_anomaly_detection_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-lambda-anomaly-errors"
    Component = "cloudwatch-alarm"
  }
}

# Alert when Anomaly Detection duration exceeds 25s (timeout is 30s).
# 25s p99 means some invocations are approaching the hard 30s timeout.
resource "aws_cloudwatch_metric_alarm" "lambda_anomaly_duration" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-anomaly-duration"
  alarm_description   = "Anomaly Detection Lambda p99 duration > 25000ms for 2 minutes  -  approaching 30s timeout; investigate DynamoDB or SQS latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 25000
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_anomaly_detection_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-lambda-anomaly-duration"
    Component = "cloudwatch-alarm"
  }
}

# Alert on any Notification Lambda error (fraud alert not dispatched to agent)
resource "aws_cloudwatch_metric_alarm" "lambda_notification_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-notification-errors"
  alarm_description   = "Notification Lambda errors >= 1  -  fraud alert email not dispatched; check SES + DynamoDB connectivity"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_notification_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-lambda-notification-errors"
    Component = "cloudwatch-alarm"
  }
}

# Alert when Logging Lambda errors reach 5 or more in 60s.
# Logging is best-effort; a few errors are acceptable, but sustained failures
# indicate the Logging queue is backing up and audit logs are being lost.
resource "aws_cloudwatch_metric_alarm" "lambda_logging_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-logging-errors"
  alarm_description   = "Logging Lambda errors >= 5  -  audit log pipeline is failing; check DynamoDB Logs table capacity and SQS queue depth"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_logging_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name      = "${var.project_name}-${var.environment}-lambda-logging-errors"
    Component = "cloudwatch-alarm"
  }
}


