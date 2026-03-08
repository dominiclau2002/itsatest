# =============================================================================
# Storage Module
#
# Contains: SFTP S3 bucket for transaction files.
# Documents and Frontend S3 buckets deferred to Phase 9.
# =============================================================================

locals {
  s3_bucket_sftp_name      = "${var.project_name}-${var.environment}-bucket-sftp"
  s3_bucket_documents_name = "${var.project_name}-${var.environment}-bucket-documents"
  s3_bucket_frontend_name  = "${var.project_name}-${var.environment}-bucket-frontend"
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


# =============================================================================
# Documents S3 Bucket — Phase 9
#
# Stores KYC documents uploaded by the Verification Lambda (e.g., identity
# proofs, signed agreements). Encrypted with the shared S3 KMS key.
# No lifecycle rule — documents are retained indefinitely; archival policy
# deferred to Phase 10.
# =============================================================================

resource "aws_s3_bucket" "documents" {
  bucket = local.s3_bucket_documents_name

  tags = {
    Name      = local.s3_bucket_documents_name
    Component = "s3-documents"
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_s3_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}


# =============================================================================
# Frontend S3 Bucket — Phase 9
#
# Hosts the compiled React SPA static assets (HTML, JS, CSS, images).
# Kept fully private — no public access, no static website hosting. CloudFront
# serves content via OAC (SigV4 signed requests); the bucket policy (in the
# cdn module, to avoid circular dependency) grants only CloudFront read access.
# Use bucket_regional_domain_name (not bucket_domain_name) for OAC — the global
# form causes 403 errors because it resolves to a different endpoint than OAC expects.
# =============================================================================

resource "aws_s3_bucket" "frontend" {
  bucket = local.s3_bucket_frontend_name

  tags = {
    Name      = local.s3_bucket_frontend_name
    Component = "s3-frontend"
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_s3_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
