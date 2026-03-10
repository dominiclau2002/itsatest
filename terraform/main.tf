# =============================================================================
# Root Module — Orchestrates all child modules
#
# Dependency order (inferred automatically from module.* references):
#   1. vpc-networking — no dependencies
#   2. auth           — no dependencies (Cognito + SES are public APIs)
#   3. security       — depends on vpc-networking (vpc_id, endpoint IDs) + auth (cognito_user_pool_arn, ses_identity_arn)
#   4. data-layer     — depends on vpc-networking + security (subnet IDs + SG IDs + KMS ARNs)
#   5. storage        — depends on security (kms_s3_arn)
#   6. serverless     — depends on security + data-layer + storage + auth
#   7. compute        — depends on vpc-networking + security + data-layer + auth + serverless (SQS URL)
#   8. cdn            — depends on storage + compute (ACM certs live at root to break circular dep)
#

data "aws_route53_zone" "main" {
  count        = var.domain_name != "" ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

# CloudFront ACM certificate — must be in us-east-1 (CloudFront requirement)
resource "aws_acm_certificate" "cloudfront" {
  count                     = var.domain_name != "" ? 1 : 0
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-cert-cloudfront"
    Component = "acm"
  }
}

# ALB ACM certificate — ap-southeast-1 (same region as ALB)
resource "aws_acm_certificate" "alb" {
  count                     = var.domain_name != "" ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-${var.environment}-cert-alb"
    Component = "acm"
  }
}

# Route 53 DNS validation records — shared by both certs (same domain = same CNAME record)
locals {
  domain_validation_options = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}
}

resource "aws_route53_record" "acm_validation" {
  for_each        = local.domain_validation_options
  zone_id         = data.aws_route53_zone.main[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

# Wait for CloudFront cert validation before passing ARN to cdn module
resource "aws_acm_certificate_validation" "cloudfront" {
  count                   = var.domain_name != "" ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Wait for ALB cert validation before passing ARN to compute module
resource "aws_acm_certificate_validation" "alb" {
  count                   = var.domain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}


module "vpc-networking" {
  source = "./modules/vpc-networking"

  aws_region               = var.aws_region
  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
}

module "auth" {
  source = "./modules/auth"

  aws_region            = var.aws_region
  project_name          = var.project_name
  environment           = var.environment
  cognito_domain_prefix = var.cognito_domain_prefix
  callback_urls         = var.callback_urls
  logout_urls           = var.logout_urls
  ses_sender_email      = var.ses_sender_email
}

module "security" {
  source = "./modules/security"

  vpc_id                     = module.vpc-networking.vpc_id
  app_port                   = var.app_port
  aws_region                 = var.aws_region
  project_name               = var.project_name
  environment                = var.environment
  secretsmanager_endpoint_id = module.vpc-networking.secretsmanager_endpoint_id
  ecr_dkr_endpoint_id        = module.vpc-networking.ecr_dkr_endpoint_id
  ecr_api_endpoint_id        = module.vpc-networking.ecr_api_endpoint_id
  cognito_user_pool_arn      = module.auth.cognito_user_pool_arn
  ses_identity_arn           = module.auth.ses_identity_arn
}

module "data-layer" {
  source = "./modules/data-layer"

  project_name                        = var.project_name
  environment                         = var.environment
  availability_zones                  = var.availability_zones
  private_db_subnet_1_id              = module.vpc-networking.private_db_subnet_1_id
  private_db_subnet_2_id              = module.vpc-networking.private_db_subnet_2_id
  sg_rds_primary_id                   = module.security.sg_rds_primary_id
  sg_elasticache_account_id           = module.security.sg_elasticache_account_id
  sg_elasticache_client_id            = module.security.sg_elasticache_client_id
  kms_rds_arn                         = module.security.kms_rds_arn
  kms_dynamodb_arn                    = module.security.kms_dynamodb_arn
  kms_elasticache_arn                 = module.security.kms_elasticache_arn
  kms_secrets_manager_arn             = module.security.kms_secrets_manager_arn
  rds_instance_class                  = var.rds_instance_class
  rds_backup_retention_days           = var.rds_backup_retention_days
  rds_database_name                   = var.rds_database_name
  rds_deletion_protection             = var.rds_deletion_protection
  rds_skip_final_snapshot             = var.rds_skip_final_snapshot
  elasticache_node_type               = var.elasticache_node_type
  elasticache_snapshot_retention_days = var.elasticache_snapshot_retention_days
}

module "storage" {
  source = "./modules/storage"

  project_name = var.project_name
  environment  = var.environment
  kms_s3_arn   = module.security.kms_s3_arn
}

module "serverless" {
  source = "./modules/serverless"

  # Core
  aws_region   = var.aws_region
  project_name = var.project_name
  environment  = var.environment

  # IAM roles (from security module — all 6 Lambda execution roles)
  iam_role_lambda_verification_arn      = module.security.iam_role_lambda_verification_arn
  iam_role_lambda_logging_arn           = module.security.iam_role_lambda_logging_arn
  iam_role_lambda_user_arn              = module.security.iam_role_lambda_user_arn
  iam_role_lambda_sftp_fetch_arn        = module.security.iam_role_lambda_sftp_fetch_arn
  iam_role_lambda_anomaly_detection_arn = module.security.iam_role_lambda_anomaly_detection_arn
  iam_role_lambda_notification_arn      = module.security.iam_role_lambda_notification_arn

  # Data layer — DynamoDB table names
  dynamodb_table_accounts_name     = module.data-layer.dynamodb_table_accounts_name
  dynamodb_table_logs_name         = module.data-layer.dynamodb_table_logs_name
  dynamodb_table_users_name        = module.data-layer.dynamodb_table_users_name
  dynamodb_table_transactions_name = module.data-layer.dynamodb_table_transactions_name

  # Storage — S3 SFTP bucket + Phase 9 Documents bucket
  s3_sftp_bucket_name      = module.storage.s3_sftp_bucket_name
  s3_documents_bucket_name = module.storage.s3_documents_bucket_name

  # Auth — Cognito + SES
  cognito_user_pool_id = module.auth.cognito_user_pool_id
  ses_sender_email     = var.ses_sender_email

  # KMS key for Lambda log group encryption (from security module)
  kms_cloudwatch_arn = module.security.kms_cloudwatch_arn

  # Config (with defaults — override in tfvars)
  lambda_log_retention_days = var.lambda_log_retention_days
  sftp_schedule_expression  = var.sftp_schedule_expression

  # Phase 10 — DynamoDB Stream ARNs for event source mappings
  dynamodb_stream_transactions_arn = module.data-layer.dynamodb_table_transactions_stream_arn
  dynamodb_stream_accounts_arn     = module.data-layer.dynamodb_table_accounts_stream_arn
}

module "compute" {
  source = "./modules/compute"

  # Core
  aws_region   = var.aws_region
  project_name = var.project_name
  environment  = var.environment
  app_port     = var.app_port

  # VPC — subnets for ALB (public) and ECS tasks (private-app)
  vpc_id                  = module.vpc-networking.vpc_id
  public_subnet_1_id      = module.vpc-networking.public_subnet_1_id
  public_subnet_2_id      = module.vpc-networking.public_subnet_2_id
  private_app_subnet_1_id = module.vpc-networking.private_app_subnet_1_id
  private_app_subnet_2_id = module.vpc-networking.private_app_subnet_2_id

  # KMS keys (from security module)
  kms_s3_arn         = module.security.kms_s3_arn         # ECR image layer encryption
  kms_cloudwatch_arn = module.security.kms_cloudwatch_arn # ECS log group encryption

  # Security groups — ALB + 4 ECS task SGs (one per service per AZ)
  sg_alb_id                   = module.security.sg_alb_id
  sg_ecs_account_primary_id   = module.security.sg_ecs_account_primary_id
  sg_ecs_account_secondary_id = module.security.sg_ecs_account_secondary_id
  sg_ecs_client_primary_id    = module.security.sg_ecs_client_primary_id
  sg_ecs_client_secondary_id  = module.security.sg_ecs_client_secondary_id

  # IAM roles — execution (ECR pull + Secrets Manager) and task (runtime permissions)
  iam_role_ecs_account_execution_arn = module.security.iam_role_ecs_account_execution_arn
  iam_role_ecs_account_task_arn      = module.security.iam_role_ecs_account_task_arn
  iam_role_ecs_client_execution_arn  = module.security.iam_role_ecs_client_execution_arn
  iam_role_ecs_client_task_arn       = module.security.iam_role_ecs_client_task_arn

  # Data layer — RDS endpoints for Client Service
  rds_cluster_endpoint = module.data-layer.rds_cluster_endpoint
  rds_cluster_port     = module.data-layer.rds_cluster_port
  rds_database_name    = module.data-layer.rds_cluster_database_name
  rds_master_username  = module.data-layer.rds_cluster_master_username

  # Data layer — DynamoDB table names for Account Service
  dynamodb_table_accounts_name     = module.data-layer.dynamodb_table_accounts_name
  dynamodb_table_transactions_name = module.data-layer.dynamodb_table_transactions_name

  # Data layer — ElastiCache endpoints
  elasticache_account_endpoint = module.data-layer.elasticache_account_primary_endpoint_address
  elasticache_account_port     = module.data-layer.elasticache_account_port
  elasticache_client_endpoint  = module.data-layer.elasticache_client_primary_endpoint_address
  elasticache_client_port      = module.data-layer.elasticache_client_port

  # Secrets Manager ARNs — injected into ECS task definitions as secrets
  secret_rds_master_password_arn = module.data-layer.secret_rds_master_password_arn
  secret_redis_account_auth_arn  = module.data-layer.secret_redis_account_auth_arn
  secret_redis_client_auth_arn   = module.data-layer.secret_redis_client_auth_arn

  # Auth — Cognito user pool ID for JWKS validation
  cognito_user_pool_id = module.auth.cognito_user_pool_id

  # Config (with defaults — override in tfvars for prod)
  ecs_task_cpu            = var.ecs_task_cpu
  ecs_task_memory         = var.ecs_task_memory
  container_image_account = var.container_image_account
  container_image_client  = var.container_image_client
  health_check_path       = var.health_check_path
  ecs_log_retention_days  = var.ecs_log_retention_days
  alb_deletion_protection = var.alb_deletion_protection

  # Phase 8 — SQS Logging queue URL from serverless module
  sqs_queue_logging_url = module.serverless.sqs_queue_logging_url

  # Phase 9 — HTTPS listener + Lambda routing
  domain_name             = var.domain_name
  acm_cert_alb_arn        = var.domain_name != "" ? aws_acm_certificate_validation.alb[0].certificate_arn : ""
  lambda_verification_arn = module.serverless.lambda_verification_arn
  lambda_user_arn         = module.serverless.lambda_user_arn

  # ALB access logs bucket (from storage module — avoids circular dep with monitoring)
  alb_logs_bucket_name = module.storage.alb_logs_bucket_name
}

module "cdn" {
  source = "./modules/cdn"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name                   = var.project_name
  environment                    = var.environment
  aws_region                     = var.aws_region
  s3_frontend_bucket_id          = module.storage.s3_frontend_bucket_id
  s3_frontend_bucket_arn         = module.storage.s3_frontend_bucket_arn
  s3_frontend_bucket_domain_name = module.storage.s3_frontend_bucket_domain_name
  alb_dns_name                   = module.compute.alb_dns_name
  alb_zone_id                    = module.compute.alb_zone_id
  domain_name                    = var.domain_name
  cloudfront_price_class         = var.cloudfront_price_class
  acm_cert_cloudfront_arn        = var.domain_name != "" ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : ""
  route53_zone_id                = var.domain_name != "" ? data.aws_route53_zone.main[0].zone_id : ""
}

module "monitoring" {
  source = "./modules/monitoring"

  # Core identity
  aws_region   = var.aws_region
  project_name = var.project_name
  environment  = var.environment

  # VPC — for VPC Flow Logs
  vpc_id = module.vpc-networking.vpc_id

  # ECS alarm dimensions (from compute module)
  ecs_cluster_name         = module.compute.ecs_cluster_name
  ecs_account_service_name = module.compute.ecs_account_primary_service_name
  ecs_client_service_name  = module.compute.ecs_client_primary_service_name

  # ALB alarm dimension — must use arn_suffix, not full ARN
  alb_arn_suffix = module.compute.alb_arn_suffix

  # RDS alarm dimension (from data-layer module)
  rds_cluster_identifier = module.data-layer.rds_cluster_identifier

  # DynamoDB alarm dimensions (all 4 table names for SystemErrors coverage)
  dynamodb_table_names = [
    module.data-layer.dynamodb_table_accounts_name,
    module.data-layer.dynamodb_table_logs_name,
    module.data-layer.dynamodb_table_users_name,
    module.data-layer.dynamodb_table_transactions_name,
  ]

  # ElastiCache alarm dimension (from data-layer module)
  elasticache_account_cluster_id = module.data-layer.elasticache_account_cluster_id

  # SQS alarm dimensions (from serverless module)
  sqs_fraud_queue_name = module.serverless.sqs_fraud_notification_queue_name
  sqs_fraud_dlq_name   = module.serverless.sqs_fraud_notification_dlq_name

  # Lambda alarm dimensions (from serverless module)
  lambda_verification_name      = module.serverless.lambda_verification_function_name
  lambda_anomaly_detection_name = module.serverless.lambda_anomaly_detection_function_name
  lambda_notification_name      = module.serverless.lambda_notification_function_name
  lambda_logging_name           = module.serverless.lambda_logging_function_name

  # KMS keys for log group encryption + CloudTrail S3 + SNS encryption (from security module)
  kms_cloudwatch_arn = module.security.kms_cloudwatch_arn
  kms_s3_arn         = module.security.kms_s3_arn

  # Optional — alarm email subscription
  alarm_email = var.alarm_email
}
