# =============================================================================
# Phase 5: S3 Buckets — SFTP Transaction Files
#
# The SFTP S3 bucket stores raw transaction files delivered by AWS Transfer
# Family SFTP server (mock core banking mainframe).
#
# IMPORTANT — Key prefix convention:
#   All transaction files MUST be written under the "transactions/" prefix.
#   The lifecycle rule below expires objects at this prefix after 90 days.
#   The SFTP Fetch Lambda reads files exclusively from "transactions/".
#   Objects outside this prefix are NOT expired and will cause unbounded growth.
#   AWS Transfer Family must be configured to drop files under transactions/.
#
# Zero-trust compliance:
#   - SSE-KMS with customer-managed key (aws_kms_key.s3)
#   - Versioning enabled (audit trail for transaction files)
#   - All public access blocked
#   - No bucket policy allowing public access
#
# Documents and Frontend S3 buckets are deferred to Phase 9.
# The S3 KMS key created in kms.tf is shared across all three buckets.
# =============================================================================


# =============================================================================
# SFTP S3 Bucket
# =============================================================================

resource "aws_s3_bucket" "sftp" {
  bucket = local.s3_bucket_sftp_name

  tags = {
    Name      = local.s3_bucket_sftp_name
    Component = "s3-sftp"
  }
}

# Versioning — maintains a full history of uploaded transaction files.
# Required for: audit trail, accidental-deletion recovery, idempotency debugging.
resource "aws_s3_bucket_versioning" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-KMS encryption at rest — customer-managed key (aws_kms_key.s3).
# All objects written to this bucket are encrypted with the S3 KMS key.
resource "aws_s3_bucket_server_side_encryption_configuration" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    # bucket_key_enabled reduces KMS API call costs by generating a per-bucket
    # data key rather than calling KMS on every object PUT.
    bucket_key_enabled = true
  }
}

# Block all public access — this bucket must never be publicly readable.
# Transaction files contain PII and financial data.
resource "aws_s3_bucket_public_access_block" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Lifecycle rule — expire processed transaction files after 90 days.
# Scope: objects under the "transactions/" prefix only.
# Files outside this prefix are not expired — see the key prefix convention note above.
# Expiration applies to all versions (current + noncurrent) after 90 days.
resource "aws_s3_bucket_lifecycle_configuration" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  rule {
    id     = "expire-processed-transactions"
    status = "Enabled"

    filter {
      # Scope to transaction drop directory only.
      # Objects outside this prefix are not managed by this rule.
      prefix = "transactions/"
    }

    expiration {
      # Expire current version after 90 days.
      # Retains 3 months of transaction history for reconciliation and audit.
      days = 90
    }

    noncurrent_version_expiration {
      # Expire previous versions after 90 days to prevent unbounded version accumulation.
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.sftp]
}
