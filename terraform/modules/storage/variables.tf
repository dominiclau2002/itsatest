variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "kms_s3_arn" {
  description = "ARN of the KMS key for S3 SSE-KMS encryption"
  type        = string
}
