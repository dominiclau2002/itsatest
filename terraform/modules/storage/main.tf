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
  s3_bucket_alb_logs_name  = "${var.project_name}-${var.environment}-bucket-alb-logs"
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

  # CKV_AWS_300: abort incomplete multipart uploads bucket-wide after 7 days.
  # A separate rule with an empty filter is required because CKV_AWS_300 checks for
  # a global abort rule  -  the prefix-scoped expiration rule below does not satisfy it.
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {} # Empty filter = apply to all objects (including non-transactions/ prefixes)

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

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
# Documents S3 Bucket  -  Phase 9
#
# Stores KYC documents uploaded by the Verification Lambda (e.g., identity
# proofs, signed agreements). Encrypted with the shared S3 KMS key.
# No lifecycle rule  -  documents are retained indefinitely; archival policy
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
# Frontend S3 Bucket  -  Phase 9
#
# Hosts the compiled React SPA static assets (HTML, JS, CSS, images).
# Kept fully private  -  no public access, no static website hosting. CloudFront
# serves content via OAC (SigV4 signed requests); the bucket policy (in the
# cdn module, to avoid circular dependency) grants only CloudFront read access.
# Use bucket_regional_domain_name (not bucket_domain_name) for OAC  -  the global
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


# =============================================================================
# ALB Access Logs S3 Bucket  -  CKV_AWS_91
#
# Receives ALB access logs delivered by the ELB service account. Created in
# the storage module (not monitoring) so the compute module can reference the
# bucket name without creating a circular dependency (storage → compute is safe;
# monitoring → compute exists for alarm dimensions, preventing compute → monitoring).
#
# ALB log delivery does NOT support KMS encryption  -  bucket must use AES256.
# The ELB service account ARN is resolved via a data source (region-agnostic).
# =============================================================================

# Regional ELB service account  -  resolves to the correct account ID for the
# current AWS region automatically, avoiding hardcoded region-specific IDs.
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket" "alb_logs" {
  bucket        = local.s3_bucket_alb_logs_name
  force_destroy = false

  tags = {
    Name      = local.s3_bucket_alb_logs_name
    Component = "alb-logs"
  }
}

# ALB log delivery does NOT support KMS  -  must use AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire ALB access logs after 90 days  -  operational data, shorter retention than audit logs
resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter {} # Empty filter = apply to all objects in the bucket

    expiration {
      days = 90
    }

    # CKV_AWS_300: abort incomplete multipart uploads to prevent orphaned part accumulation
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy: Allow the regional ELB service account to deliver access logs.
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowELBServiceAccountPut"
      Effect = "Allow"
      Principal = {
        AWS = data.aws_elb_service_account.main.arn
      }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.alb_logs.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
