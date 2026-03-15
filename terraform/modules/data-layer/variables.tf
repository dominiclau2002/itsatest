variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones used for resources"
  type        = list(string)
}

variable "private_db_subnet_1_id" {
  description = "ID of the primary private database subnet (AZ-1a)"
  type        = string
}

variable "private_db_subnet_2_id" {
  description = "ID of the standby private database subnet (AZ-1b)"
  type        = string
}

variable "sg_rds_primary_id" {
  description = "Security group ID for Aurora RDS"
  type        = string
}

variable "sg_elasticache_account_id" {
  description = "Security group ID for ElastiCache Account Redis cluster"
  type        = string
}

variable "sg_elasticache_client_id" {
  description = "Security group ID for ElastiCache Client Redis cluster"
  type        = string
}

variable "kms_rds_arn" {
  description = "ARN of the KMS key for RDS encryption"
  type        = string
}

variable "kms_dynamodb_arn" {
  description = "ARN of the KMS key for DynamoDB encryption"
  type        = string
}

variable "kms_elasticache_arn" {
  description = "ARN of the KMS key for ElastiCache encryption"
  type        = string
}

variable "kms_secrets_manager_arn" {
  description = "ARN of the KMS key for Secrets Manager encryption"
  type        = string
}

variable "create_rds_cluster" {
  description = "Set to false to skip Aurora cluster creation (required on free-tier AWS accounts which do not support Aurora without WithExpressConfiguration). Set true once the account is upgraded."
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS Aurora instance class for writer and reader nodes"
  type        = string
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain RDS automated backups"
  type        = number
}

variable "rds_database_name" {
  description = "Name of the initial PostgreSQL database created on the Aurora cluster"
  type        = string
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection on the Aurora cluster"
  type        = bool
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on cluster deletion"
  type        = bool
}

variable "elasticache_node_type" {
  description = "ElastiCache node type for Redis clusters"
  type        = string
}

variable "elasticache_snapshot_retention_days" {
  description = "Number of days to retain automatic ElastiCache Redis snapshots"
  type        = number
}

variable "dynamodb_deletion_protection" {
  description = "Enable deletion protection on all DynamoDB tables"
  type        = bool
}
