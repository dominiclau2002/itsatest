# =============================================================================
# Auth Module  -  Cognito User Pool, OAuth 2.0 App Client, SES Email Identity
#
# This module must never reference module.security outputs to avoid circular
# dependency. Dependency direction: auth -> security (auth outputs feed into
# security inputs via root main.tf).
#
# Resources: 1 data source, 1 user pool, 1 domain, 1 client, 2 groups, 1 SES identity
# =============================================================================

# -----------------------------------------------------------------------------
# Data source  -  needed for SES ARN construction in outputs
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Cognito User Pool  -  identity store with MFA enforcement and SRP password security
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-user-pool"

  # MFA is required for all users (TOTP only  -  no SMS to avoid SNS complexity)
  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  # Password policy  -  enforced server-side by Cognito using SRP protocol
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Users sign in with email address (not a separate username)
  username_attributes = ["email"]

  # Auto-verify email on signup (Cognito sends verification code)
  auto_verified_attributes = ["email"]

  # Account recovery via verified email only
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Email attribute  -  required and mutable
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-user-pool"
    Component = "cognito"
  }
}

# -----------------------------------------------------------------------------
# Cognito User Pool Domain  -  hosted UI endpoint for OAuth 2.0 Authorization Code flow
# Domain prefix must be globally unique across all AWS accounts
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "main" {
  domain       = coalesce(var.cognito_domain_prefix, "${var.project_name}-${var.environment}")
  user_pool_id = aws_cognito_user_pool.main.id
}

# -----------------------------------------------------------------------------
# Cognito User Pool Client  -  public client for SPA (PKCE, no client secret)
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client  -  SPA uses PKCE for token exchange, no client secret needed
  generate_secret = false

  # OAuth 2.0 Authorization Code flow with PKCE
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "profile", "email"]
  supported_identity_providers         = ["COGNITO"]

  # Redirect URLs  -  environment-specific (localhost for dev, CloudFront for prod)
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Only allow refresh token auth from the SPA client
  # Admin API calls from User Lambda (AdminInitiateAuth) bypass app client
  # explicit_auth_flows  -  these only govern what the SPA client can initiate
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Security  -  prevent username enumeration via error messages
  prevent_user_existence_errors = "ENABLED"
}

# -----------------------------------------------------------------------------
# Cognito User Groups  -  RBAC via cognito:groups claim in JWT access tokens
# -----------------------------------------------------------------------------

# Admin group  -  full access to accounts, clients, users, and system configuration
resource "aws_cognito_user_group" "admin" {
  name         = "Admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "CRM Administrators  -  full access to accounts, clients, users, and system configuration"
}

# Agent group  -  client management and transaction review access
resource "aws_cognito_user_group" "agent" {
  name         = "Agent"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "CRM Agents  -  client management and transaction review access"
}

# -----------------------------------------------------------------------------
# SES Email Identity  -  verified sender for Verification and Notification Lambdas
#
# After first terraform apply, manual email verification is required:
# check the inbox of ses_sender_email and click the verification link.
# Verification and Notification Lambdas cannot send email until this is completed.
# -----------------------------------------------------------------------------
resource "aws_ses_email_identity" "sender" {
  email = var.ses_sender_email
}
