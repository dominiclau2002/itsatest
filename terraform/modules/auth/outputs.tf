output "cognito_user_pool_id" {
  description = "Cognito user pool ID  -  used for JWKS URL construction and ECS env vars in Phase 7"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "Full Cognito user pool ARN  -  used to scope IAM policies in security module (replaces userpool/* wildcard)"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_user_pool_endpoint" {
  description = "Cognito user pool endpoint  -  base URL for JWKS discovery"
  value       = aws_cognito_user_pool.main.endpoint
}

output "cognito_client_id" {
  description = "Cognito app client ID  -  used for frontend OAuth 2.0 configuration in Phase 9"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_domain" {
  description = "Full Cognito hosted UI domain URL"
  value       = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "ses_identity_arn" {
  description = "Constructed SES email identity ARN  -  aws_ses_email_identity has no .arn attribute in provider 5.x"
  value       = "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/${aws_ses_email_identity.sender.email}"
}
