variable "aws_region" {
  description = "AWS region for ARN construction"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "cognito_domain_prefix" {
  description = "Cognito hosted UI domain prefix (must be globally unique across all AWS accounts). Defaults to project_name-environment if null."
  type        = string
  default     = null
}

variable "callback_urls" {
  description = "OAuth 2.0 callback URLs for the Cognito app client (e.g., http://localhost:3000/callback for dev)"
  type        = list(string)
}

variable "logout_urls" {
  description = "OAuth 2.0 logout redirect URLs for the Cognito app client"
  type        = list(string)
}

variable "ses_sender_email" {
  description = "Email address to verify as SES sender identity for Verification and Notification Lambdas"
  type        = string
}
