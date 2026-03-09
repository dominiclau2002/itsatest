output "s3_sftp_bucket_name" {
  description = "SFTP S3 bucket name"
  value       = aws_s3_bucket.sftp.id
}

output "s3_sftp_bucket_arn" {
  description = "SFTP S3 bucket ARN"
  value       = aws_s3_bucket.sftp.arn
}

output "s3_documents_bucket_name" {
  description = "Documents S3 bucket name — injected into Verification Lambda as S3_BUCKET_DOCUMENTS env var"
  value       = aws_s3_bucket.documents.id
}

output "s3_documents_bucket_arn" {
  description = "Documents S3 bucket ARN — for future IAM policy scoping"
  value       = aws_s3_bucket.documents.arn
}

output "s3_frontend_bucket_id" {
  description = "Frontend S3 bucket ID (name) — passed to cdn module for bucket policy and OAC association"
  value       = aws_s3_bucket.frontend.id
}

output "s3_frontend_bucket_arn" {
  description = "Frontend S3 bucket ARN — scopes the OAC S3 bucket policy in cdn module"
  value       = aws_s3_bucket.frontend.arn
}

output "s3_frontend_bucket_domain_name" {
  description = "Frontend S3 bucket regional domain name — must use regional form (bucket_regional_domain_name) for OAC; global form (bucket_domain_name) causes runtime 403"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "alb_logs_bucket_name" {
  description = "ALB access logs S3 bucket name — passed to compute module for access_logs block (CKV_AWS_91)"
  value       = aws_s3_bucket.alb_logs.id
}
