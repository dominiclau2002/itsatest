# =============================================================================
# Phase 5: KMS Customer-Managed Keys
#
# One key per AWS service family — service-specific keys limit blast radius:
# a compromised key can only expose data encrypted by that specific service.
# All keys have annual rotation enabled (AWS rotates the key material automatically;
# old versions are retained for decryption of existing ciphertext).
#
# Key policy pattern per key:
#   1. Root account principal — full administrative control (break-glass)
#   2. Service principal — minimum permissions required by the AWS service
#      to perform envelope encryption/decryption on your behalf
#
# Aliases follow the pattern: alias/${project_name}-${environment}-[service]
# =============================================================================


# =============================================================================
# KMS Key 1: RDS Aurora
#
# Used by: aws_rds_cluster.primary (storage encryption at rest)
#          Aurora Performance Insights (kms_key_id on each instance)
# Service principal: rds.amazonaws.com
# =============================================================================
resource "aws_kms_key" "rds" {
  description             = "Customer-managed KMS key for Aurora RDS storage encryption and Performance Insights"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account — full administrative control (key creation, policy updates, deletion)
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # RDS service principal — minimum permissions for envelope encryption.
        # GenerateDataKey: encrypt new Aurora storage pages
        # Decrypt: decrypt pages on read
        # DescribeKey: validate the key is usable before Aurora starts
        Sid    = "RDSServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-rds"
    Component = "kms-rds"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}


# =============================================================================
# KMS Key 2: DynamoDB
#
# Used by: all 4 DynamoDB tables (Accounts, Logs, Users, Transactions)
# Service principal: dynamodb.amazonaws.com
# =============================================================================
resource "aws_kms_key" "dynamodb" {
  description             = "Customer-managed KMS key for DynamoDB table encryption (Accounts, Logs, Users, Transactions)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # DynamoDB service principal — envelope encryption for table items.
        # CreateGrant: required for DynamoDB to create grants allowing read/write operations.
        Sid    = "DynamoDBServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-dynamodb"
    Component = "kms-dynamodb"
  }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.project_name}-${var.environment}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}


# =============================================================================
# KMS Key 3: ElastiCache
#
# Used by: both Redis replication groups (Account + Client) at-rest encryption
# Service principal: elasticache.amazonaws.com
# =============================================================================
resource "aws_kms_key" "elasticache" {
  description             = "Customer-managed KMS key for ElastiCache Redis at-rest encryption (Account and Client clusters)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # ElastiCache service principal — at-rest encryption for Redis data.
        Sid    = "ElastiCacheServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "elasticache.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-elasticache"
    Component = "kms-elasticache"
  }
}

resource "aws_kms_alias" "elasticache" {
  name          = "alias/${var.project_name}-${var.environment}-elasticache"
  target_key_id = aws_kms_key.elasticache.key_id
}


# =============================================================================
# KMS Key 4: S3
#
# Used by: SFTP S3 bucket (Phase 5); Documents and Frontend S3 buckets (Phase 9)
# No service principal needed — S3 uses the caller's IAM permissions for
# envelope encryption. Access is governed by IAM policies on the Lambda/ECS roles.
# =============================================================================
resource "aws_kms_key" "s3" {
  description             = "Customer-managed KMS key for S3 SSE-KMS encryption (SFTP bucket Phase 5; Documents + Frontend buckets Phase 9)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account — full administrative control.
        # Individual Lambda/ECS roles are granted access via IAM policy (KMSAccessS3 statements).
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-s3"
    Component = "kms-s3"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}


# =============================================================================
# KMS Key 5: Secrets Manager
#
# Used by: all Secrets Manager secrets created in Phase 5
#          (rds-master-password, redis-account-auth, redis-client-auth)
#          and all Phase 6 secrets (Cognito client secret, API keys).
# Service principal: secretsmanager.amazonaws.com
# =============================================================================
resource "aws_kms_key" "secrets_manager" {
  description             = "Customer-managed KMS key for Secrets Manager secrets (RDS password, Redis auth tokens, Phase 6 secrets)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Secrets Manager service principal — encrypt/decrypt secret values at rest.
        # GenerateDataKey: encrypt a new secret value or rotation
        # Decrypt: retrieve secret value on GetSecretValue calls
        # DescribeKey: health-check on key availability
        Sid    = "SecretsManagerServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-secretsmanager"
    Component = "kms-secretsmanager"
  }
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${var.project_name}-${var.environment}-secretsmanager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}
