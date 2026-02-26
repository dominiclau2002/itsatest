# =============================================================================
# Security Module
#
# Contains: Security groups, KMS keys, IAM roles & policies, VPC endpoint
# SG associations. All security concerns consolidated in one module.
#
# Source files: security_groups.tf, kms.tf, iam.tf, ECR endpoint SG from
# vpc_endpoints.tf, plus 3 aws_vpc_endpoint_security_group_association
# resources that attach SGs to VPC endpoints created in vpc-networking.
# =============================================================================


# =============================================================================
# Module-Level Locals
#
# Recomputed from project_name + environment (same formulas as root locals.tf).
# Modules do not inherit root locals — must be defined locally.
# =============================================================================
locals {
  # DynamoDB table names
  dynamodb_table_accounts_name     = "${var.project_name}-${var.environment}-table-accounts"
  dynamodb_table_logs_name         = "${var.project_name}-${var.environment}-table-logs"
  dynamodb_table_users_name        = "${var.project_name}-${var.environment}-table-users"
  dynamodb_table_transactions_name = "${var.project_name}-${var.environment}-table-transactions"

  # SQS queue names
  sqs_queue_logging_name            = "${var.project_name}-${var.environment}-queue-logging"
  sqs_queue_fraud_notification_name = "${var.project_name}-${var.environment}-queue-fraud-notification"

  # S3 bucket names
  s3_bucket_sftp_name      = "${var.project_name}-${var.environment}-bucket-sftp"
  s3_bucket_documents_name = "${var.project_name}-${var.environment}-bucket-documents"

  # ECR repository names
  ecr_repo_account_service_name = "${var.project_name}-${var.environment}-account-service"
  ecr_repo_client_service_name  = "${var.project_name}-${var.environment}-client-service"

  # Secrets Manager path prefixes
  secrets_prefix_account = "${var.project_name}/${var.environment}/account-service"
  secrets_prefix_client  = "${var.project_name}/${var.environment}/client-service"
  secrets_prefix_sftp    = "${var.project_name}/${var.environment}/sftp"

  # CloudWatch log group names — ECS
  log_group_ecs_account = "/ecs/${var.project_name}-${var.environment}-account-service"
  log_group_ecs_client  = "/ecs/${var.project_name}-${var.environment}-client-service"

  # CloudWatch log group names — Lambda
  log_group_lambda_verification = "/aws/lambda/${var.project_name}-${var.environment}-verification"
  log_group_lambda_logging      = "/aws/lambda/${var.project_name}-${var.environment}-logging"
  log_group_lambda_user         = "/aws/lambda/${var.project_name}-${var.environment}-user"
  log_group_lambda_sftp_fetch   = "/aws/lambda/${var.project_name}-${var.environment}-sftp-fetch"
  log_group_lambda_anomaly      = "/aws/lambda/${var.project_name}-${var.environment}-anomaly-detection"
  log_group_lambda_notification = "/aws/lambda/${var.project_name}-${var.environment}-notification"
}


# =============================================================================
# Data Sources
# =============================================================================

# Used for ARN construction throughout this module (KMS key policies + IAM policies).
data "aws_caller_identity" "current" {}

# CloudFront managed prefix list — restricts ALB ingress to CloudFront edge nodes only.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}


# =============================================================================
# Security Groups — Phase 3
#
# Protects all in-VPC resources: ALB, ECS (Account & Client services),
# RDS Aurora, ElastiCache Redis, and VPC endpoint ENIs.
# =============================================================================

# =============================================================================
# 1. ALB Security Group
# =============================================================================
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-sg-alb"
  description = "ALB: accept HTTPS from CloudFront prefix list; egress to ECS tasks on app_port"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-alb"
    Component = "alb"
  }
}

resource "aws_security_group_rule" "alb_ingress_https_cloudfront" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from CloudFront edge nodes only - WAF bypass prevention"
}

resource "aws_security_group_rule" "alb_egress_ecs_account_primary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Account Service primary tasks in AZ-1a"
}

resource "aws_security_group_rule" "alb_egress_ecs_account_secondary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Account Service secondary tasks in AZ-1b"
}

resource "aws_security_group_rule" "alb_egress_ecs_client_primary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Client Service primary tasks in AZ-1a"
}

resource "aws_security_group_rule" "alb_egress_ecs_client_secondary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Client Service secondary tasks in AZ-1b"
}

# =============================================================================
# 2. ECS Account Service - Primary (private-app-1, ap-southeast-1a)
# =============================================================================
resource "aws_security_group" "ecs_account_primary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-account-primary"
  description = "ECS Account Service primary (AZ-1a): ALB ingress; ElastiCache/Secrets/NAT egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-ecs-account-primary"
    Component = "ecs-account-primary"
  }
}

resource "aws_security_group_rule" "ecs_account_primary_ingress_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Receive application traffic from ALB only"
}

resource "aws_security_group_rule" "ecs_account_primary_egress_alb" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Stateful return path to ALB (health checks and response routing)"
}

resource "aws_security_group_rule" "ecs_account_primary_egress_elasticache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticache_account.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Account Service cache reads/writes - ElastiCache Account cluster"
}

resource "aws_security_group_rule" "ecs_account_primary_egress_secretsmanager" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secretsmanager_endpoint.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Retrieve secrets via Secrets Manager PrivateLink (no internet exposure)"
}

resource "aws_security_group_rule" "ecs_account_primary_egress_nat" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_account_primary.id
  description       = "DynamoDB, SQS, Cognito, CloudWatch route via NAT Gateway by architecture decision - VPC endpoints deliberately absent for these services"
}

# =============================================================================
# 3. ECS Account Service - Secondary (private-app-2, ap-southeast-1b)
# =============================================================================
resource "aws_security_group" "ecs_account_secondary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-account-secondary"
  description = "ECS Account Service secondary (AZ-1b): ALB ingress; ElastiCache/Secrets/NAT egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-ecs-account-secondary"
    Component = "ecs-account-secondary"
  }
}

resource "aws_security_group_rule" "ecs_account_secondary_ingress_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_account_secondary.id
  description              = "Receive application traffic from ALB only"
}

resource "aws_security_group_rule" "ecs_account_secondary_egress_alb" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_account_secondary.id
  description              = "Stateful return path to ALB (health checks and response routing)"
}

resource "aws_security_group_rule" "ecs_account_secondary_egress_elasticache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticache_account.id
  security_group_id        = aws_security_group.ecs_account_secondary.id
  description              = "Account Service cache reads/writes - ElastiCache Account cluster"
}

resource "aws_security_group_rule" "ecs_account_secondary_egress_secretsmanager" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secretsmanager_endpoint.id
  security_group_id        = aws_security_group.ecs_account_secondary.id
  description              = "Retrieve secrets via Secrets Manager PrivateLink (no internet exposure)"
}

resource "aws_security_group_rule" "ecs_account_secondary_egress_nat" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_account_secondary.id
  description       = "DynamoDB, SQS, Cognito, CloudWatch route via NAT Gateway by architecture decision - VPC endpoints deliberately absent for these services"
}

# =============================================================================
# 4. ECS Client Service - Primary (private-app-1, ap-southeast-1a)
# =============================================================================
resource "aws_security_group" "ecs_client_primary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-client-primary"
  description = "ECS Client Service primary (AZ-1a): ALB ingress; RDS/ElastiCache/Secrets/NAT egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-ecs-client-primary"
    Component = "ecs-client-primary"
  }
}

resource "aws_security_group_rule" "ecs_client_primary_ingress_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Receive application traffic from ALB only"
}

resource "aws_security_group_rule" "ecs_client_primary_egress_alb" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Stateful return path to ALB (health checks and response routing)"
}

resource "aws_security_group_rule" "ecs_client_primary_egress_rds_primary" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds_primary.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "PostgreSQL write queries to Aurora RDS primary writer node"
}

resource "aws_security_group_rule" "ecs_client_primary_egress_elasticache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticache_client.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Client Service cache reads/writes - ElastiCache Client cluster"
}

resource "aws_security_group_rule" "ecs_client_primary_egress_secretsmanager" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secretsmanager_endpoint.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Retrieve secrets via Secrets Manager PrivateLink (no internet exposure)"
}

resource "aws_security_group_rule" "ecs_client_primary_egress_nat" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_client_primary.id
  description       = "SQS, Cognito, CloudWatch route via NAT Gateway by architecture decision - VPC endpoints deliberately absent for these services"
}

# =============================================================================
# 5. ECS Client Service - Secondary (private-app-2, ap-southeast-1b)
# =============================================================================
resource "aws_security_group" "ecs_client_secondary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-client-secondary"
  description = "ECS Client Service secondary (AZ-1b): ALB ingress; RDS/ElastiCache/Secrets/NAT egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-ecs-client-secondary"
    Component = "ecs-client-secondary"
  }
}

resource "aws_security_group_rule" "ecs_client_secondary_ingress_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "Receive application traffic from ALB only"
}

resource "aws_security_group_rule" "ecs_client_secondary_egress_alb" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "Stateful return path to ALB (health checks and response routing)"
}

resource "aws_security_group_rule" "ecs_client_secondary_egress_rds_primary" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds_primary.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "PostgreSQL write queries to Aurora RDS primary writer node"
}

resource "aws_security_group_rule" "ecs_client_secondary_egress_elasticache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticache_client.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "Client Service cache reads/writes - ElastiCache Client cluster"
}

resource "aws_security_group_rule" "ecs_client_secondary_egress_secretsmanager" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secretsmanager_endpoint.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "Retrieve secrets via Secrets Manager PrivateLink (no internet exposure)"
}

resource "aws_security_group_rule" "ecs_client_secondary_egress_nat" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_client_secondary.id
  description       = "SQS, Cognito, CloudWatch route via NAT Gateway by architecture decision - VPC endpoints deliberately absent for these services"
}

# =============================================================================
# 6. RDS Security Group (private-db-1 and private-db-2)
# =============================================================================
resource "aws_security_group" "rds_primary" {
  name        = "${var.project_name}-${var.environment}-sg-rds-primary"
  description = "RDS Aurora writer and reader (single SG — failover safe): PostgreSQL from Client Service only; no egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-rds-primary"
    Component = "rds-primary"
  }
}

resource "aws_security_group_rule" "rds_primary_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.rds_primary.id
  description              = "Client Service primary tasks - read/write client profile records (AZ-1a)"
}

resource "aws_security_group_rule" "rds_primary_ingress_ecs_client_secondary" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.rds_primary.id
  description              = "Client Service secondary tasks - read/write client profile records (AZ-1b)"
}

# =============================================================================
# 7. ElastiCache Account Security Group
# =============================================================================
resource "aws_security_group" "elasticache_account" {
  name        = "${var.project_name}-${var.environment}-sg-elasticache-account"
  description = "ElastiCache Redis for Account Service: Redis from Account ECS tasks only; no egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-elasticache-account"
    Component = "elasticache-account"
  }
}

resource "aws_security_group_rule" "elasticache_account_ingress_ecs_account_primary" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.elasticache_account.id
  description              = "Account Service primary tasks - cache reads and writes (AZ-1a)"
}

resource "aws_security_group_rule" "elasticache_account_ingress_ecs_account_secondary" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.elasticache_account.id
  description              = "Account Service secondary tasks - cache reads and writes (AZ-1b)"
}

# =============================================================================
# 8. ElastiCache Client Security Group
# =============================================================================
resource "aws_security_group" "elasticache_client" {
  name        = "${var.project_name}-${var.environment}-sg-elasticache-client"
  description = "ElastiCache Redis for Client Service: Redis from Client ECS tasks only; no egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-elasticache-client"
    Component = "elasticache-client"
  }
}

resource "aws_security_group_rule" "elasticache_client_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.elasticache_client.id
  description              = "Client Service primary tasks - cache reads and writes (AZ-1a)"
}

resource "aws_security_group_rule" "elasticache_client_ingress_ecs_client_secondary" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.elasticache_client.id
  description              = "Client Service secondary tasks - cache reads and writes (AZ-1b)"
}

# =============================================================================
# 9. Secrets Manager VPC Endpoint Security Group
# =============================================================================
resource "aws_security_group" "secretsmanager_endpoint" {
  name        = "${var.project_name}-${var.environment}-sg-secretsmanager-endpoint"
  description = "Secrets Manager PrivateLink endpoint ENI: HTTPS from ECS tasks only; no egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-secretsmanager-endpoint"
    Component = "secretsmanager-endpoint"
  }
}

resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_account_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Account Service primary tasks fetch credentials via PrivateLink (AZ-1a)"
}

resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_account_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Account Service secondary tasks fetch credentials via PrivateLink (AZ-1b)"
}

resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Client Service primary tasks fetch credentials via PrivateLink (AZ-1a)"
}

resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_client_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Client Service secondary tasks fetch credentials via PrivateLink (AZ-1b)"
}

# =============================================================================
# 10. ECR Endpoint Security Group
# =============================================================================
resource "aws_security_group" "ecr_endpoint" {
  name        = "${var.project_name}-${var.environment}-sg-ecr-endpoint"
  description = "ECR PrivateLink endpoint ENI: HTTPS from ECS tasks only; no egress"
  vpc_id      = var.vpc_id

  tags = {
    Name      = "${var.project_name}-${var.environment}-sg-ecr-endpoint"
    Component = "ecr-endpoint"
  }
}

# ECR endpoint ingress rules (from each ECS task SG)
resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_account_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Account Service primary tasks pull container image from ECR (AZ-1a)"
}

resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_account_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Account Service secondary tasks pull container image from ECR (AZ-1b)"
}

resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Client Service primary tasks pull container image from ECR (AZ-1a)"
}

resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_client_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Client Service secondary tasks pull container image from ECR (AZ-1b)"
}

# ECS egress rules to ECR endpoint
resource "aws_security_group_rule" "ecs_account_primary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

resource "aws_security_group_rule" "ecs_account_secondary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_account_secondary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

resource "aws_security_group_rule" "ecs_client_primary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

resource "aws_security_group_rule" "ecs_client_secondary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}


# =============================================================================
# VPC Endpoint Security Group Associations
#
# These associate security groups (defined above) with VPC endpoints (created
# in the vpc-networking module). This pattern breaks the circular dependency:
# vpc-networking creates endpoints without SGs, security module attaches SGs.
# Reference: hashicorp/aws provider aws_vpc_endpoint_security_group_association
# =============================================================================

resource "aws_vpc_endpoint_security_group_association" "secretsmanager" {
  vpc_endpoint_id   = var.secretsmanager_endpoint_id
  security_group_id = aws_security_group.secretsmanager_endpoint.id
}

resource "aws_vpc_endpoint_security_group_association" "ecr_dkr" {
  vpc_endpoint_id   = var.ecr_dkr_endpoint_id
  security_group_id = aws_security_group.ecr_endpoint.id
}

resource "aws_vpc_endpoint_security_group_association" "ecr_api" {
  vpc_endpoint_id   = var.ecr_api_endpoint_id
  security_group_id = aws_security_group.ecr_endpoint.id
}


# =============================================================================
# KMS Customer-Managed Keys — Phase 5
# =============================================================================

resource "aws_kms_key" "rds" {
  description             = "Customer-managed KMS key for Aurora RDS storage encryption and Performance Insights"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "RDSServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-rds"
    Component = "kms-rds"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "dynamodb" {
  description             = "Customer-managed KMS key for DynamoDB table encryption (Accounts, Logs, Users, Transactions)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "DynamoDBServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-dynamodb"
    Component = "kms-dynamodb"
  }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.project_name}-${var.environment}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_kms_key" "elasticache" {
  description             = "Customer-managed KMS key for ElastiCache Redis at-rest encryption (Account and Client clusters)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "ElastiCacheServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "elasticache.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-elasticache"
    Component = "kms-elasticache"
  }
}

resource "aws_kms_alias" "elasticache" {
  name          = "alias/${var.project_name}-${var.environment}-elasticache"
  target_key_id = aws_kms_key.elasticache.key_id
}

resource "aws_kms_key" "s3" {
  description             = "Customer-managed KMS key for S3 SSE-KMS encryption (SFTP bucket Phase 5; Documents + Frontend buckets Phase 9)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-s3"
    Component = "kms-s3"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "secrets_manager" {
  description             = "Customer-managed KMS key for Secrets Manager secrets (RDS password, Redis auth tokens, Phase 6 secrets)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerServiceEncryption"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name      = "${var.project_name}-${var.environment}-kms-secretsmanager"
    Component = "kms-secretsmanager"
  }
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${var.project_name}-${var.environment}-secretsmanager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}


# =============================================================================
# IAM Roles & Policies — Phase 4
# =============================================================================

# Trust Policy Documents (shared across role families)
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


# --- ECS Account Service Execution Role ---

resource "aws_iam_role" "ecs_execution_role_account" {
  name               = "${var.project_name}-${var.environment}-role-ecs-execution-account"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "ECS task execution role for Account Service — ECR image pull, Secrets Manager secret injection, CloudWatch log stream creation"
}

data "aws_iam_policy_document" "ecs_execution_policy_account" {
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPullAccountService"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${local.ecr_repo_account_service_name}",
    ]
  }

  statement {
    sid    = "CloudWatchLogsAccount"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_ecs_account}:*",
    ]
  }

  statement {
    sid       = "SecretsManagerAccountService"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secrets_prefix_account}/*"]
  }
}

resource "aws_iam_policy" "ecs_execution_policy_account" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-execution-account"
  description = "Execution-time permissions for Account Service ECS agent: ECR pull, Secrets Manager injection, CloudWatch log writes"
  policy      = data.aws_iam_policy_document.ecs_execution_policy_account.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_account" {
  role       = aws_iam_role.ecs_execution_role_account.name
  policy_arn = aws_iam_policy.ecs_execution_policy_account.arn
}

# --- ECS Client Service Execution Role ---

resource "aws_iam_role" "ecs_execution_role_client" {
  name               = "${var.project_name}-${var.environment}-role-ecs-execution-client"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "ECS task execution role for Client Service — ECR image pull, Secrets Manager secret injection (RDS password, Redis auth token), CloudWatch log stream creation"
}

data "aws_iam_policy_document" "ecs_execution_policy_client" {
  statement {
    sid       = "ECRAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPullClientService"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${local.ecr_repo_client_service_name}",
    ]
  }

  statement {
    sid    = "CloudWatchLogsClient"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_ecs_client}:*",
    ]
  }

  statement {
    sid       = "SecretsManagerClientService"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secrets_prefix_client}/*"]
  }
}

resource "aws_iam_policy" "ecs_execution_policy_client" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-execution-client"
  description = "Execution-time permissions for Client Service ECS agent: ECR pull, Secrets Manager injection (RDS password, Redis auth), CloudWatch log writes"
  policy      = data.aws_iam_policy_document.ecs_execution_policy_client.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_client" {
  role       = aws_iam_role.ecs_execution_role_client.name
  policy_arn = aws_iam_policy.ecs_execution_policy_client.arn
}


# --- ECS Account Service Task Role ---

resource "aws_iam_role" "ecs_task_role_account" {
  name               = "${var.project_name}-${var.environment}-role-ecs-task-account"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "Runtime role for Account Service container — Accounts DynamoDB CRUD, Transactions DynamoDB read/update (agent review dashboard), SQS logging"
}

data "aws_iam_policy_document" "ecs_task_policy_account" {
  statement {
    sid    = "DynamoDBAccountsTableCRUD"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}/index/*",
    ]
  }

  statement {
    sid    = "DynamoDBTransactionsAgentReview"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}/index/*",
    ]
  }

  statement {
    sid     = "SQSSendToLoggingQueue"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_logging_name}",
    ]
  }

  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "ecs_task_policy_account" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-task-account"
  description = "Runtime permissions for Account Service container: Accounts DynamoDB CRUD, Transactions DynamoDB read/update (agent review), SQS logging"
  policy      = data.aws_iam_policy_document.ecs_task_policy_account.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_account" {
  role       = aws_iam_role.ecs_task_role_account.name
  policy_arn = aws_iam_policy.ecs_task_policy_account.arn
}

# --- ECS Client Service Task Role ---

resource "aws_iam_role" "ecs_task_role_client" {
  name               = "${var.project_name}-${var.environment}-role-ecs-task-client"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  description        = "Runtime role for Client Service container — SQS logging only. RDS credentials injected at startup via execution role; no IAM auth for RDS."
}

data "aws_iam_policy_document" "ecs_task_policy_client" {
  statement {
    sid     = "SQSSendToLoggingQueue"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_logging_name}",
    ]
  }

  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "ecs_task_policy_client" {
  name        = "${var.project_name}-${var.environment}-policy-ecs-task-client"
  description = "Runtime permissions for Client Service container: SQS logging only. Client data stored in Aurora RDS — no DynamoDB access."
  policy      = data.aws_iam_policy_document.ecs_task_policy_client.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_client" {
  role       = aws_iam_role.ecs_task_role_client.name
  policy_arn = aws_iam_policy.ecs_task_policy_client.arn
}


# --- Lambda 1: Verification Lambda ---

resource "aws_iam_role" "lambda_execution_role_verification" {
  name               = "${var.project_name}-${var.environment}-role-lambda-verification"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Verification Lambda — SES email, S3 document storage, Cognito user attribute update"
}

data "aws_iam_policy_document" "lambda_policy_verification" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_verification}:*",
    ]
  }

  statement {
    sid    = "SESSendVerificationEmail"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = [
      "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*",
    ]
  }

  statement {
    sid    = "S3StoreKYCDocuments"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = [
      "arn:aws:s3:::${local.s3_bucket_documents_name}/*",
    ]
  }

  statement {
    sid    = "KMSAccessS3"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.s3.arn,
    ]
  }

  statement {
    sid    = "CognitoUpdateVerifiedAttributes"
    effect = "Allow"
    actions = [
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminGetUser",
    ]
    resources = [
      "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/*",
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_verification" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-verification"
  description = "Permissions for Verification Lambda: SES email, S3 KYC document storage, Cognito user attribute update"
  policy      = data.aws_iam_policy_document.lambda_policy_verification.json
}

resource "aws_iam_role_policy_attachment" "lambda_verification" {
  role       = aws_iam_role.lambda_execution_role_verification.name
  policy_arn = aws_iam_policy.lambda_policy_verification.arn
}

# --- Lambda 2: Logging Lambda ---

resource "aws_iam_role" "lambda_execution_role_logging" {
  name               = "${var.project_name}-${var.environment}-role-lambda-logging"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Logging Lambda — SQS Logging queue consumer, DynamoDB Logs table writer"
}

data "aws_iam_policy_document" "lambda_policy_logging" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_logging}:*",
    ]
  }

  statement {
    sid    = "SQSConsumeLoggingQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_logging_name}",
    ]
  }

  statement {
    sid     = "DynamoDBWriteLogsTable"
    effect  = "Allow"
    actions = ["dynamodb:PutItem"]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_logs_name}",
    ]
  }

  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_logging" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-logging"
  description = "Permissions for Logging Lambda: SQS Logging queue consumer (receive/delete), DynamoDB Logs table writer (PutItem only)"
  policy      = data.aws_iam_policy_document.lambda_policy_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_execution_role_logging.name
  policy_arn = aws_iam_policy.lambda_policy_logging.arn
}

# --- Lambda 3: User Lambda ---

resource "aws_iam_role" "lambda_execution_role_user" {
  name               = "${var.project_name}-${var.environment}-role-lambda-user"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for User Lambda — Cognito Admin API for user lifecycle, User DynamoDB for CRM metadata"
}

data "aws_iam_policy_document" "lambda_policy_user" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_user}:*",
    ]
  }

  statement {
    sid    = "CognitoAdminUserManagement"
    effect = "Allow"
    actions = [
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:AdminDisableUser",
      "cognito-idp:AdminUpdateUserAttributes",
      "cognito-idp:AdminInitiateAuth",
      "cognito-idp:AdminGetUser",
    ]
    resources = [
      "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/*",
    ]
  }

  statement {
    sid    = "DynamoDBUsersTable"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}/index/*",
    ]
  }

  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_user" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-user"
  description = "Permissions for User Lambda: Cognito Admin API (user lifecycle), User DynamoDB (CRM metadata). No DeleteItem — soft-delete only."
  policy      = data.aws_iam_policy_document.lambda_policy_user.json
}

resource "aws_iam_role_policy_attachment" "lambda_user" {
  role       = aws_iam_role.lambda_execution_role_user.name
  policy_arn = aws_iam_policy.lambda_policy_user.arn
}

# --- Lambda 4: SFTP Fetch Lambda ---

resource "aws_iam_role" "lambda_execution_role_sftp_fetch" {
  name               = "${var.project_name}-${var.environment}-role-lambda-sftp-fetch"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for SFTP Fetch Lambda — Transfer Family endpoint resolution, Secrets Manager SSH key, EventBridge publish"
}

data "aws_iam_policy_document" "lambda_policy_sftp_fetch" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_sftp_fetch}:*",
    ]
  }

  statement {
    sid     = "TransferFamilyDescribeServer"
    effect  = "Allow"
    actions = ["transfer:DescribeServer"]
    resources = [
      "arn:aws:transfer:${var.aws_region}:${data.aws_caller_identity.current.account_id}:server/*",
    ]
  }

  statement {
    sid     = "SecretsManagerSFTPKey"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secrets_prefix_sftp}/*",
    ]
  }

  statement {
    sid     = "S3ListSFTPBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${local.s3_bucket_sftp_name}",
    ]
  }

  statement {
    sid    = "S3AccessSFTPTransactionFiles"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = [
      "arn:aws:s3:::${local.s3_bucket_sftp_name}/transactions/*",
    ]
  }

  statement {
    sid    = "KMSAccessS3"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.s3.arn,
    ]
  }

  statement {
    sid     = "EventBridgePublishTransactions"
    effect  = "Allow"
    actions = ["events:PutEvents"]
    resources = [
      "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:event-bus/default",
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_sftp_fetch" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-sftp-fetch"
  description = "Permissions for SFTP Fetch Lambda: Transfer Family server describe, Secrets Manager SSH key, S3 SFTP bucket (list + read + tag for idempotency), EventBridge publish"
  policy      = data.aws_iam_policy_document.lambda_policy_sftp_fetch.json
}

resource "aws_iam_role_policy_attachment" "lambda_sftp_fetch" {
  role       = aws_iam_role.lambda_execution_role_sftp_fetch.name
  policy_arn = aws_iam_policy.lambda_policy_sftp_fetch.arn
}

# --- Lambda 5: Anomaly Detection Lambda ---

resource "aws_iam_role" "lambda_execution_role_anomaly_detection" {
  name               = "${var.project_name}-${var.environment}-role-lambda-anomaly-detection"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Anomaly Detection Lambda — Transactions DynamoDB (read baseline + write result), SQS Fraud Notification queue producer"
}

data "aws_iam_policy_document" "lambda_policy_anomaly_detection" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_anomaly}:*",
    ]
  }

  statement {
    sid    = "DynamoDBTransactionsReadBaseline"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}/index/*",
    ]
  }

  statement {
    sid    = "DynamoDBTransactionsWriteResult"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_transactions_name}",
    ]
  }

  statement {
    sid     = "SQSSendFraudNotification"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_fraud_notification_name}",
    ]
  }

  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_anomaly_detection" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-anomaly-detection"
  description = "Permissions for Anomaly Detection Lambda: Transactions DynamoDB (read historical baseline, write scored result), SQS Fraud Notification queue producer"
  policy      = data.aws_iam_policy_document.lambda_policy_anomaly_detection.json
}

resource "aws_iam_role_policy_attachment" "lambda_anomaly_detection" {
  role       = aws_iam_role.lambda_execution_role_anomaly_detection.name
  policy_arn = aws_iam_policy.lambda_policy_anomaly_detection.arn
}

# --- Lambda 6: Notification Lambda ---

resource "aws_iam_role" "lambda_execution_role_notification" {
  name               = "${var.project_name}-${var.environment}-role-lambda-notification"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for Notification Lambda — SQS Fraud Notification queue consumer, SES fraud alert email to agent"
}

data "aws_iam_policy_document" "lambda_policy_notification" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_lambda_notification}:*",
    ]
  }

  statement {
    sid    = "SQSConsumeFraudNotificationQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_queue_fraud_notification_name}",
    ]
  }

  statement {
    sid    = "SESSendFraudAlertToAgent"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = [
      "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*",
    ]
  }

  statement {
    sid    = "DynamoDBAccountsReadAgentId"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_accounts_name}/index/*",
    ]
  }

  statement {
    sid    = "DynamoDBUsersReadAgentEmail"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.dynamodb_table_users_name}/index/*",
    ]
  }

  statement {
    sid    = "KMSAccessDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.dynamodb.arn,
    ]
  }
}

resource "aws_iam_policy" "lambda_policy_notification" {
  name        = "${var.project_name}-${var.environment}-policy-lambda-notification"
  description = "Permissions for Notification Lambda: SQS Fraud Notification queue consumer (receive/delete), Accounts DynamoDB (get agent_id), Users DynamoDB (get agent_email), SES fraud alert email to agent"
  policy      = data.aws_iam_policy_document.lambda_policy_notification.json
}

resource "aws_iam_role_policy_attachment" "lambda_notification" {
  role       = aws_iam_role.lambda_execution_role_notification.name
  policy_arn = aws_iam_policy.lambda_policy_notification.arn
}
