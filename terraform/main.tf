# =============================================================================
# Root Module — Orchestrates all child modules
#
# Dependency order (inferred automatically from module.* references):
#   1. vpc-networking — no dependencies
#   2. security       — depends on vpc-networking (vpc_id, endpoint IDs)
#   3. data-layer     — depends on vpc-networking + security (subnet IDs + SG IDs + KMS ARNs)
#   4. storage        — depends on security (kms_s3_arn)
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
