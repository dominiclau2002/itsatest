# =============================================================================
# Storage Module
#
# Contains: SFTP S3 bucket for transaction files.
# Documents and Frontend S3 buckets deferred to Phase 9.
# =============================================================================

locals {
  s3_bucket_sftp_name = "${var.project_name}-${var.environment}-bucket-sftp"
}

resource "aws_s3_bucket" "sftp" {
  bucket = local.s3_bucket_sftp_name

  tags = {
    Name      = local.s3_bucket_sftp_name
    Component = "s3-sftp"
  }
}

resource "aws_s3_bucket_versioning" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_s3_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "sftp" {
  bucket = aws_s3_bucket.sftp.id

  rule {
    id     = "expire-processed-transactions"
    status = "Enabled"

    filter {
      prefix = "transactions/"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.sftp]
}
