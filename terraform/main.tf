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
# =============================================================================

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

  # Storage — S3 SFTP bucket
  s3_sftp_bucket_name = module.storage.s3_sftp_bucket_name

  # Auth — Cognito + SES
  cognito_user_pool_id = module.auth.cognito_user_pool_id
  ses_sender_email     = var.ses_sender_email

  # Config (with defaults — override in tfvars)
  lambda_log_retention_days = var.lambda_log_retention_days
  sftp_schedule_expression  = var.sftp_schedule_expression
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
}
