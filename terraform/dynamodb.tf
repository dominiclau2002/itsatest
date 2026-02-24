# =============================================================================
# Phase 5: DynamoDB Tables
#
# Four tables for the CRM system, all with:
#   - PAY_PER_REQUEST billing (variable load; no capacity forecasting needed)
#   - Customer-managed KMS encryption (aws_kms_key.dynamodb)
#   - Point-in-time recovery (PITR) enabled
#   - deletion_protection_enabled = false (dev environment)
#
# Table names come from locals.tf (established in Phase 4 and used in IAM policies).
# =============================================================================


# =============================================================================
# Table 1: Accounts
#
# Owned by Account Service. Stores account-level data per client.
# agent_id is a non-key attribute written by the application (not declared
# as a DynamoDB Attribute in Terraform — only key and GSI attributes need
# explicit declarations). Notification Lambda reads agent_id via ClientIndex GSI.
#
# Streams: NEW_AND_OLD_IMAGES — supports future event-driven triggers
# (e.g. account status change → EventBridge).
# =============================================================================
resource "aws_dynamodb_table" "accounts" {
  name             = local.dynamodb_table_accounts_name
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "account_id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Encryption at rest — customer-managed KMS key
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  # Point-in-time recovery — continuous backup with 35-day window
  point_in_time_recovery {
    enabled = true
  }

  # Deletion protection disabled in dev (allow terraform destroy for teardown)
  deletion_protection_enabled = false

  # Primary key
  attribute {
    name = "account_id"
    type = "S"
  }

  # GSI key — required DynamoDB attribute declaration
  attribute {
    name = "client_id"
    type = "S"
  }

  # ClientIndex GSI — query accounts by client_id.
  # Used by: Account Service (list accounts for a client)
  #          Notification Lambda (look up agent_id for a flagged client account)
  # NOTE: agent_id is stored as a non-key attribute in each item — it is not
  # declared here but MUST be written by Account Service on every PutItem.
  global_secondary_index {
    name            = "ClientIndex"
    hash_key        = "client_id"
    projection_type = "ALL"
  }

  tags = {
    Name      = local.dynamodb_table_accounts_name
    Component = "dynamodb-accounts"
  }
}


# =============================================================================
# Table 2: Logs
#
# Write-once audit log table. Owned by Logging Lambda (SQS consumer).
# Every agent/admin action on client or account data produces one log entry.
#
# IMPORTANT — Two timestamp attributes with distinct purposes:
#   datetime   (S, ISO 8601): human-readable application timestamp, part of the
#              log schema shown in audit reports. Range key for time-ordered queries.
#   expires_at (N, epoch seconds): DynamoDB TTL attribute — triggers automatic item
#              deletion after the specified Unix timestamp. NOT ISO 8601.
#              The Logging Lambda MUST write BOTH on every PutItem:
#                datetime   = "2026-02-25T14:30:00Z"  (ISO 8601 string)
#                expires_at = 1772053800               (Unix epoch integer)
#              Providing ISO 8601 for expires_at will silently fail TTL deletion.
#
# Streams: disabled — Logs table is write-only; no downstream event triggers needed.
# =============================================================================
resource "aws_dynamodb_table" "logs" {
  name         = local.dynamodb_table_logs_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "log_id"
  range_key    = "datetime"

  # Streams disabled — Logs table is append-only; no event-driven processing needed.
  stream_enabled = false

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  attribute {
    name = "log_id"
    type = "S"
  }

  # datetime (S) — ISO 8601 string. Range key for time-ordered query access.
  # Used by audit reports to display human-readable event timestamps.
  attribute {
    name = "datetime"
    type = "S"
  }

  # expires_at (N) — DynamoDB TTL attribute (Unix epoch seconds).
  # DISTINCT from datetime: this is a numeric TTL value for automatic deletion,
  # not the human-readable ISO 8601 timestamp. DynamoDB TTL silently ignores
  # non-numeric values — writing ISO 8601 here would prevent expiry.
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Name      = local.dynamodb_table_logs_name
    Component = "dynamodb-logs"
  }
}


# =============================================================================
# Table 3: Users
#
# CRM user metadata table. Managed by User Lambda (Traffic Flow 6).
# Cognito is the system of record for passwords; DynamoDB stores CRM metadata
# (role, status, email) that Cognito does not natively support.
# Soft-delete pattern: status='inactive' (no DeleteItem — see iam.tf).
#
# Streams: disabled — user state changes do not trigger downstream events.
# =============================================================================
resource "aws_dynamodb_table" "users" {
  name         = local.dynamodb_table_users_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  stream_enabled = false

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  # user_id maps to Cognito sub (UUID format)
  attribute {
    name = "user_id"
    type = "S"
  }

  # GSI key — required attribute declaration
  attribute {
    name = "email"
    type = "S"
  }

  # EmailIndex GSI — query users by email address.
  # Used by: User Lambda for email-based lookups during authentication and
  #          duplicate-check before creating a new user.
  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = {
    Name      = local.dynamodb_table_users_name
    Component = "dynamodb-users"
  }
}


# =============================================================================
# Table 4: Transactions
#
# Primary transaction ledger. Written by SFTP Fetch Lambda (initial PutItem),
# scored by Anomaly Detection Lambda (UpdateItem with status + risk_score),
# and reviewed by agents via Account Service dashboard (UpdateItem with decision).
#
# Streams: NEW_AND_OLD_IMAGES — enables future reconciliation event triggers
# (e.g. status='rejected' → EventBridge → core banking reversal).
# =============================================================================
resource "aws_dynamodb_table" "transactions" {
  name             = local.dynamodb_table_transactions_name
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "transaction_id"
  range_key        = "timestamp"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  # GSI key — required attribute declaration
  attribute {
    name = "client_id"
    type = "S"
  }

  # ClientTimeIndex GSI — query transactions by client + time window.
  # Used by: Anomaly Detection Lambda (last 100 transactions per client as baseline)
  #          Account Service dashboard (paginated transaction history per client)
  global_secondary_index {
    name            = "ClientTimeIndex"
    hash_key        = "client_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  tags = {
    Name      = local.dynamodb_table_transactions_name
    Component = "dynamodb-transactions"
  }
}
