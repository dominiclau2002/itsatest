output "s3_sftp_bucket_name" {
  description = "SFTP S3 bucket name"
  value       = aws_s3_bucket.sftp.id
}

output "s3_sftp_bucket_arn" {
  description = "SFTP S3 bucket ARN"
  value       = aws_s3_bucket.sftp.arn
}
