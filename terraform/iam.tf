# =============================================================================
# Phase 4: IAM Roles & Policies
#
# Creates all service roles before any compute or data resources are provisioned.
# Phases 5–9 (ECS, Lambda, RDS, DynamoDB, SQS) depend on these roles existing.
#
# Design principles:
#   - Exact ARNs specified for all resources (wildcards documented with justification)
#   - Separate role per service — no shared execution roles between services
#   - Policy documents defined as data sources — no inline policies
#   - Trust policies reused across service families (ECS, Lambda) for DRY config
#
# Resource naming: ${project_name}-${environment}-role-[component]
#                  ${project_name}-${environment}-policy-[component]
# =============================================================================


# =============================================================================
# Data Sources
# =============================================================================

# Used for ARN construction throughout this file.
# Avoids hardcoding the AWS account ID.
data "aws_caller_identity" "current" {}


# =============================================================================
# Trust Policy Documents (shared across role families)
# =============================================================================

# ECS trust policy — used by all 4 ECS execution and task roles.
# Allows the ECS service to assume these roles on behalf of containers.
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Lambda trust policy — used by all 6 Lambda execution roles.
# Allows the Lambda service to assume these roles on behalf of function invocations.
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


# =============================================================================
# ECS Task Execution Roles (2)
#
# Used by the ECS agent (not the application container) to:
#   - Pull container images from ECR at task start
#   - Inject Secrets Manager values as environment variables at container start
#   - Write container stdout/stderr to CloudWatch Logs
#
# The execution role is NOT available to application code at runtime.
# =============================================================================

# --- Account Service Execution Role ---

resource "aws_iam_role" "ecs_execution_role_account" {
  name               = "${var.project_name}-${var.environment}-role-ecs-execution-account"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "ECS task execution role for Account Service — ECR image pull, Secrets Manager secret injection, CloudWatch log stream creation"
}

data "aws_iam_policy_document" "ecs_execution_policy_account" {
  # ecr:GetAuthorizationToken — wildcard resource is required per AWS documentation.
  # The authorization token is account-scoped and cannot be restricted to
  # individual repositories. This is a known ECR API constraint, not a policy gap.
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Pull the Account Service container image from its dedicated ECR repository.
  statement {
    sid    = "ECRPullAccountService"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${local.ecr_repo_account_service_name}",
    ]
  }

  # Write container logs to the Account Service CloudWatch log group.
  statement {
    sid    = "CloudWatchLogsAccount"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_ecs_account}:*",
    ]
  }

  # Inject Account Service secrets at container startup (app config, service credentials).
  statement {
    sid       = "SecretsManagerAccountService"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secrets_prefix_account}/*"]
  }
}

resource "aws_iam_policy" "ecs_execution_policy_account" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-execution-account"
  description = "Execution-time permissions for Account Service ECS agent: ECR pull, Secrets Manager injection, CloudWatch log writes"
  policy      = data.aws_iam_policy_document.ecs_execution_policy_account.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_account" {
  role       = aws_iam_role.ecs_execution_role_account.name
  policy_arn = aws_iam_policy.ecs_execution_policy_account.arn
}

# --- Client Service Execution Role ---

resource "aws_iam_role" "ecs_execution_role_client" {
  name               = "${var.project_name}-${var.environment}-role-ecs-execution-client"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "ECS task execution role for Client Service — ECR image pull, Secrets Manager secret injection (RDS password, Redis auth token), CloudWatch log stream creation"
}

data "aws_iam_policy_document" "ecs_execution_policy_client" {
  # ecr:GetAuthorizationToken — wildcard required per AWS ECR API constraint (see Account role comment).
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Pull the Client Service container image from its dedicated ECR repository.
  statement {
    sid    = "ECRPullClientService"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${local.ecr_repo_client_service_name}",
    ]
  }

  # Write container logs to the Client Service CloudWatch log group.
  statement {
    sid    = "CloudWatchLogsClient"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_ecs_client}:*",
    ]
  }

  # Inject Client Service secrets at container startup.
  # Includes: Aurora RDS password, ElastiCache Redis auth token.
  statement {
    sid       = "SecretsManagerClientService"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secrets_prefix_client}/*"]
  }
}

resource "aws_iam_policy" "ecs_execution_policy_client" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-execution-client"
  description = "Execution-time permissions for Client Service ECS agent: ECR pull, Secrets Manager injection (RDS password, Redis auth), CloudWatch log writes"
  policy      = data.aws_iam_policy_document.ecs_execution_policy_client.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_client" {
  role       = aws_iam_role.ecs_execution_role_client.name
  policy_arn = aws_iam_policy.ecs_execution_policy_client.arn
}


# =============================================================================
# ECS Task Roles (2)
#
# Used by the running application container (not the ECS agent) at runtime.
# Grants permissions for the service's business logic — DynamoDB operations,
# SQS sends, etc. These credentials are available to application code via
# the EC2 instance metadata endpoint inside the container.
# =============================================================================

# --- Account Service Task Role ---
#
# Account Service responsibilities:
#   - Full CRUD on Accounts DynamoDB (owns this table)
#   - Read/update access on Transactions DynamoDB (serves agent review dashboard)
#     NOTE: If a dedicated Transaction Service ECS task is added in Phase 7,
#     the Transactions DynamoDB permissions should move to that task role.
#   - SQS SendMessage to Logging queue (audit trail)
#   - No RDS access — Account Service data is DynamoDB-only (confirmed by SG rules)

resource "aws_iam_role" "ecs_task_role_account" {
  name               = "${var.project_name}-${var.environment}-role-ecs-task-account"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "Runtime role for Account Service container — Accounts DynamoDB CRUD, Transactions DynamoDB read/update (agent review dashboard), SQS logging"
}

data "aws_iam_policy_document" "ecs_task_policy_account" {
  # Full CRUD on the Accounts table — Account Service is the sole owner of this table.
  statement {
    sid    = "DynamoDBAccountsTableCRUD"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}",
      # GSI access — queries by client ID and other secondary indexes
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}/index/*",
    ]
  }

  # Transactions table access for the agent review dashboard.
  # The React dashboard queries Account Service → Account Service polls Transactions DynamoDB.
  # GetItem/Query: retrieve flagged transactions for agent review
  # UpdateItem: agent marks a flagged transaction as reviewed (status update)
  # NOTE: If a Transaction Service ECS task is introduced in Phase 7, move this block there.
  statement {
    sid    = "DynamoDBTransactionsAgentReview"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}",
      # ClientTimeIndex GSI — list transactions by client + timestamp for review polling
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}/index/*",
    ]
  }

  # Send audit events to the centralized Logging queue.
  # Logging Lambda consumes from this queue and writes to the Logs DynamoDB table.
  statement {
    sid     = "SQSSendToLoggingQueue"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_logging_name}",
    ]
  }

  # KMS permissions for DynamoDB table encryption (defense-in-depth: IAM policy + key policy dual authorization).
  # Required so Account Service container can read/write KMS-encrypted DynamoDB items at runtime.
  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "ecs_task_policy_account" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-task-account"
  description = "Runtime permissions for Account Service container: Accounts DynamoDB CRUD, Transactions DynamoDB read/update (agent review), SQS logging"
  policy      = data.aws_iam_policy_document.ecs_task_policy_account.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_account" {
  role       = aws_iam_role.ecs_task_role_account.name
  policy_arn = aws_iam_policy.ecs_task_policy_account.arn
}

# --- Client Service Task Role ---
#
# Client Service responsibilities:
#   - Aurora RDS for client profile data (connection credentials injected via execution role)
#   - SQS SendMessage to Logging queue (audit trail)
#   - No DynamoDB access — Client Service data layer is Aurora RDS only (confirmed by SG rules)

resource "aws_iam_role" "ecs_task_role_client" {
  name               = "${var.project_name}-${var.environment}-role-ecs-task-client"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "Runtime role for Client Service container — SQS logging only. RDS credentials injected at startup via execution role; no IAM auth for RDS."
}

data "aws_iam_policy_document" "ecs_task_policy_client" {
  # Send audit events to the centralized Logging queue.
  # Client Service has no DynamoDB runtime permissions — its data layer is Aurora RDS.
  # RDS connection credentials are injected at container startup via the execution role.
  statement {
    sid     = "SQSSendToLoggingQueue"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_logging_name}",
    ]
  }

  # KMS permissions for DynamoDB table encryption (defense-in-depth).
  # Client Service task role does not access DynamoDB directly, but this permission
  # is included for consistency in case DynamoDB-backed features are added to Client Service.
  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "ecs_task_policy_client" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-task-client"
  description = "Runtime permissions for Client Service container: SQS logging only. Client data stored in Aurora RDS — no DynamoDB access."
  policy      = data.aws_iam_policy_document.ecs_task_policy_client.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_client" {
  role       = aws_iam_role.ecs_task_role_client.name
  policy_arn = aws_iam_policy.ecs_task_policy_client.arn
}


# =============================================================================
# Lambda Execution Roles (6)
#
# All Lambda functions operate outside the VPC (no VPC attachment, no SG needed).
# Each function has its own execution role — no shared roles between functions.
# =============================================================================

# --- Lambda 1: Verification Lambda ---
#
# Traffic Flow 4: Client onboarding.
# Sends a verification email via SES, stores identity documents in S3,
# and updates the client's Cognito user attributes (e.g. email_verified).

resource "aws_iam_role" "lambda_execution_role_verification" {
  name               = "${var.project_name}-${var.environment}-role-lambda-verification"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Verification Lambda — SES email, S3 document storage, Cognito user attribute update"
}

data "aws_iam_policy_document" "lambda_policy_verification" {
  # Write Lambda execution logs.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_verification}:*",
    ]
  }

  # Send verification emails to onboarding clients.
  # identity/* is account-scoped. Specific SES identity ARN (domain/email) locked in Phase 6
  # when the SES verified identity is created.
  statement {
    sid    = "SESSendVerificationEmail"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = [
      "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*",
    ]
  }

  # Store client KYC identity documents uploaded during onboarding.
  statement {
    sid    = "S3StoreKYCDocuments"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${local.s3_bucket_documents_name}/*",
    ]
  }

  # KMS permissions for S3 SSE-KMS encryption on the Documents bucket (Phase 9).
  # S3 KMS key created in Phase 5 — Documents bucket deferred to Phase 9.
  statement {
    sid    = "KMSAccessS3"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.s3.arn,
    ]
  }

  # Update the client's Cognito user attributes after verification (e.g. email_verified, kyc_status).
  # userpool/* is account-scoped. Specific User Pool ID locked in Phase 6 when pool is created.
  statement {
    sid    = "CognitoUpdateVerifiedAttributes"
    effect = "Allow"
    actions = [
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminGetUser",
    ]
    resources = [
      "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/*",
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_verification" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-verification"
  description = "Permissions for Verification Lambda: SES email, S3 KYC document storage, Cognito user attribute update"
  policy      = data.aws_iam_policy_document.lambda_policy_verification.json
}

resource "aws_iam_role_policy_attachment" "lambda_verification" {
  role       = aws_iam_role.lambda_execution_role_verification.name
  policy_arn = aws_iam_policy.lambda_policy_verification.arn
}

# --- Lambda 2: Logging Lambda ---
#
# Traffic Flow 5: Centralized audit logging.
# Polls the SQS Logging queue and writes audit records to the Logs DynamoDB table.
# Triggered by SQS event source mapping — not invoked directly.

resource "aws_iam_role" "lambda_execution_role_logging" {
  name               = "${var.project_name}-${var.environment}-role-lambda-logging"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Logging Lambda — SQS Logging queue consumer, DynamoDB Logs table writer"
}

data "aws_iam_policy_document" "lambda_policy_logging" {
  # Write Lambda execution logs.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_logging}:*",
    ]
  }

  # Consume audit messages from the centralized Logging SQS queue.
  # GetQueueAttributes is required for the SQS event source mapping health check.
  statement {
    sid    = "SQSConsumeLoggingQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_logging_name}",
    ]
  }

  # Write audit records to the centralized Logs DynamoDB table.
  # PutItem only — Logging Lambda never reads or mutates existing records.
  statement {
    sid     = "DynamoDBWriteLogsTable"
    effect  = "Allow"
    actions = ["dynamodb:PutItem"]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_logs_name}",
    ]
  }

  # KMS permissions for DynamoDB table encryption (defense-in-depth).
  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_logging" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-logging"
  description = "Permissions for Logging Lambda: SQS Logging queue consumer (receive/delete), DynamoDB Logs table writer (PutItem only)"
  policy      = data.aws_iam_policy_document.lambda_policy_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_execution_role_logging.name
  policy_arn = aws_iam_policy.lambda_policy_logging.arn
}

# --- Lambda 3: User Lambda ---
#
# Traffic Flow 6: Admin user management.
# Operations: Create, Disable, Update, Authenticate, Reset Password.
# Cognito is the system of record for identity and password.
# User DynamoDB table stores CRM metadata: role, status, email.
# Both systems are updated atomically per operation.

resource "aws_iam_role" "lambda_execution_role_user" {
  name               = "${var.project_name}-${var.environment}-role-lambda-user"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for User Lambda — Cognito Admin API for user lifecycle, User DynamoDB for CRM metadata"
}

data "aws_iam_policy_document" "lambda_policy_user" {
  # Write Lambda execution logs.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_user}:*",
    ]
  }

  # Cognito Admin API — exact actions per business operation:
  #   CREATE:          AdminCreateUser + AdminSetUserPassword
  #   DISABLE:         AdminDisableUser
  #   UPDATE:          AdminUpdateUserAttributes
  #   AUTHENTICATE:    AdminInitiateAuth
  #   RESET PASSWORD:  AdminSetUserPassword
  #   READ (validate): AdminGetUser
  #
  # userpool/* is scoped to this account. Specific User Pool ID locked in Phase 6.
  statement {
    sid    = "CognitoAdminUserManagement"
    effect = "Allow"
    actions = [
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:AdminDisableUser",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminInitiateAuth",
      "cognito-idp:AdminGetUser",
    ]
    resources = [
      "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/*",
    ]
  }

  # User CRM metadata table — maps user_id to { role, email, status }.
  #   PutItem:    CREATE — write new user record with status='active'
  #   UpdateItem: DISABLE — set status='inactive'; UPDATE — update role/email
  #   GetItem/Query: read-before-write validation
  # No DeleteItem — soft-delete only (status='inactive') per architecture decision.
  statement {
    sid    = "DynamoDBUsersTable"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}/index/*",
    ]
  }

  # KMS permissions for DynamoDB table encryption (defense-in-depth).
  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_user" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-user"
  description = "Permissions for User Lambda: Cognito Admin API (user lifecycle), User DynamoDB (CRM metadata). No DeleteItem — soft-delete only."
  policy      = data.aws_iam_policy_document.lambda_policy_user.json
}

resource "aws_iam_role_policy_attachment" "lambda_user" {
  role       = aws_iam_role.lambda_execution_role_user.name
  policy_arn = aws_iam_policy.lambda_policy_user.arn
}

# --- Lambda 4: SFTP Fetch Lambda ---
#
# Traffic Flow 7, Step 1: Scheduled by EventBridge.
# Retrieves batched transaction files from AWS Transfer Family SFTP server.
# SSH private key for SFTP authentication is stored in Secrets Manager.
# Publishes "transaction-for-review" events to EventBridge for downstream processing.

resource "aws_iam_role" "lambda_execution_role_sftp_fetch" {
  name               = "${var.project_name}-${var.environment}-role-lambda-sftp-fetch"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for SFTP Fetch Lambda — Transfer Family endpoint resolution, Secrets Manager SSH key, EventBridge publish"
}

data "aws_iam_policy_document" "lambda_policy_sftp_fetch" {
  # Write Lambda execution logs.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_sftp_fetch}:*",
    ]
  }

  # Describe the SFTP server to resolve its endpoint hostname.
  # SFTP data-plane operations (file download) use SSH key auth — no IAM required.
  statement {
    sid     = "TransferFamilyDescribeServer"
    effect  = "Allow"
    actions = ["transfer:DescribeServer"]
    resources = [
      "arn:aws:transfer:${var.aws_region}:${data.aws_caller_identity.current.account_id}:server/*",
    ]
  }

  # Retrieve the SSH private key used for SFTP authentication from Secrets Manager.
  statement {
    sid     = "SecretsManagerSFTPKey"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secrets_prefix_sftp}/*",
    ]
  }

  # List the SFTP bucket at each cron invocation to discover available transaction files.
  # Bucket-level resource (no trailing /*) is required for s3:ListBucket per AWS IAM rules.
  # Bucket deferred to Phase 5 (S3 data storage). Bucket name locked in via local.s3_bucket_sftp_name.
  statement {
    sid     = "S3ListSFTPBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${local.s3_bucket_sftp_name}",
    ]
  }

  # Access raw transaction files in the SFTP bucket:
  #   GetObject:       read the transaction file content
  #   GetObjectTagging: check whether the file was already processed (idempotency)
  #   PutObjectTagging: mark the file as processed after successful ingestion
  # Path prefix /transactions/* scopes access to the transaction drop directory only.
  statement {
    sid    = "S3AccessSFTPTransactionFiles"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = [
      "arn:aws:s3:::${local.s3_bucket_sftp_name}/transactions/*",
    ]
  }

  # KMS permissions for SFTP S3 bucket SSE-KMS encryption (defense-in-depth).
  statement {
    sid    = "KMSAccessS3"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.s3.arn,
    ]
  }

  # Publish transaction events to the EventBridge default event bus.
  # Default bus confirmed for Phase 4. Custom bus decision deferred to Phase 8 (EventBridge).
  statement {
    sid     = "EventBridgePublishTransactions"
    effect  = "Allow"
    actions = ["events:PutEvents"]
    resources = [
      "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:event-bus/default",
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_sftp_fetch" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-sftp-fetch"
  description = "Permissions for SFTP Fetch Lambda: Transfer Family server describe, Secrets Manager SSH key, S3 SFTP bucket (list + read + tag for idempotency), EventBridge publish"
  policy      = data.aws_iam_policy_document.lambda_policy_sftp_fetch.json
}

resource "aws_iam_role_policy_attachment" "lambda_sftp_fetch" {
  role       = aws_iam_role.lambda_execution_role_sftp_fetch.name
  policy_arn = aws_iam_policy.lambda_policy_sftp_fetch.arn
}

# --- Lambda 5: Anomaly Detection Lambda ---
#
# Traffic Flow 7, Steps 2–3: Triggered by EventBridge per incoming transaction.
# Queries the Transactions DynamoDB table for historical baseline data,
# scores the transaction, and writes the result:
#   - Normal:   PutItem with status='completed'
#   - Flagged:  PutItem with status='flagged' + SendMessage to Fraud Notification queue

resource "aws_iam_role" "lambda_execution_role_anomaly_detection" {
  name               = "${var.project_name}-${var.environment}-role-lambda-anomaly-detection"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Anomaly Detection Lambda — Transactions DynamoDB (read baseline + write result), SQS Fraud Notification queue producer"
}

data "aws_iam_policy_document" "lambda_policy_anomaly_detection" {
  # Write Lambda execution logs.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_anomaly}:*",
    ]
  }

  # Query the Transactions table for historical baseline (recent transactions per client).
  # ClientTimeIndex GSI: query transactions by client_id + timestamp for anomaly window.
  statement {
    sid    = "DynamoDBTransactionsReadBaseline"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}/index/*",
    ]
  }

  # Write the scored transaction record with status='completed' or status='flagged'.
  # UpdateItem: updates an existing transaction record written by SFTP Fetch Lambda.
  statement {
    sid    = "DynamoDBTransactionsWriteResult"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}",
    ]
  }

  # Send flagged transaction details to the Fraud Notification queue.
  # Notification Lambda consumes this queue and emails the responsible agent.
  statement {
    sid     = "SQSSendFraudNotification"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_fraud_notification_name}",
    ]
  }

  # KMS permissions for DynamoDB table encryption (defense-in-depth).
  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_anomaly_detection" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-anomaly-detection"
  description = "Permissions for Anomaly Detection Lambda: Transactions DynamoDB (read historical baseline, write scored result), SQS Fraud Notification queue producer"
  policy      = data.aws_iam_policy_document.lambda_policy_anomaly_detection.json
}

resource "aws_iam_role_policy_attachment" "lambda_anomaly_detection" {
  role       = aws_iam_role.lambda_execution_role_anomaly_detection.name
  policy_arn = aws_iam_policy.lambda_policy_anomaly_detection.arn
}

# --- Lambda 6: Notification Lambda ---
#
# Traffic Flow 7, Step 3a: Triggered by the SQS Fraud Notification queue.
# Composes and sends a fraud alert email to the agent responsible for
# the flagged account via AWS SES.

resource "aws_iam_role" "lambda_execution_role_notification" {
  name               = "${var.project_name}-${var.environment}-role-lambda-notification"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Notification Lambda — SQS Fraud Notification queue consumer, SES fraud alert email to agent"
}

data "aws_iam_policy_document" "lambda_policy_notification" {
  # Write Lambda execution logs.
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_notification}:*",
    ]
  }

  # Consume fraud notification messages from the Fraud Notification SQS queue.
  # GetQueueAttributes is required for the SQS event source mapping health check.
  statement {
    sid    = "SQSConsumeFraudNotificationQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_fraud_notification_name}",
    ]
  }

  # Send fraud alert emails to the agent responsible for the flagged account.
  # identity/* is account-scoped. Specific SES identity ARN locked in Phase 6
  # when the SES verified domain/email identity is created.
  statement {
    sid    = "SESSendFraudAlertToAgent"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = [
      "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*",
    ]
  }

  # Look up agent_id from the Accounts table using client_id received in the SQS payload.
  # The Accounts table includes agent_id as an attribute (owner of the client account).
  # NOTE: agent_id must be included in the Account table schema when created in Phase 5.
  statement {
    sid    = "DynamoDBAccountsReadAgentId"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}/index/*",
    ]
  }

  # Fetch agent_email from the Users table using agent_id obtained from the Accounts table.
  # Required to address the fraud alert email to the correct agent.
  statement {
    sid    = "DynamoDBUsersReadAgentEmail"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}/index/*",
    ]
  }

  # KMS permissions for DynamoDB table encryption (defense-in-depth).
  # Notification Lambda reads from Accounts and Users tables — both encrypted with this key.
  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_notification" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-notification"
  description = "Permissions for Notification Lambda: SQS Fraud Notification queue consumer (receive/delete), Accounts DynamoDB (get agent_id), Users DynamoDB (get agent_email), SES fraud alert email to agent"
  policy      = data.aws_iam_policy_document.lambda_policy_notification.json
}

resource "aws_iam_role_policy_attachment" "lambda_notification" {
  role       = aws_iam_role.lambda_execution_role_notification.name
  policy_arn = aws_iam_policy.lambda_policy_notification.arn
}
