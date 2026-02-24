variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "profile" {
  description = "AWS profile name"
  type        = string
  default     = "dominic-admin"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "itsa-testing-setup"
}



variable "enable_encryption" {
  description = "Enable encryption for resources"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones used for resources"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets (ECS)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private database subnets (RDS, ElastiCache)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "app_port" {
  description = "Port that ECS application containers listen on (used in ALB target group and security group rules)"
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port > 1024 && var.app_port <= 65535
    error_message = "app_port must be an unprivileged port (1025-65535)."
  }
}

# =============================================================================
# Phase 5: Data Storage Variables
# =============================================================================

variable "rds_instance_class" {
  description = "RDS Aurora instance class for writer and reader nodes (e.g. db.t3.medium for dev, db.r6g.large for prod)"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain RDS automated backups (minimum 7 for dev, 30 for prod)"
  type        = number
  default     = 7

  validation {
    condition     = var.rds_backup_retention_days >= 7
    error_message = "rds_backup_retention_days must be at least 7."
  }
}

variable "rds_database_name" {
  description = "Name of the initial PostgreSQL database created on the Aurora cluster"
  type        = string
  default     = "crmdb"
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection on the Aurora cluster. Defaults to true for prod parity. Set to false only when terraform destroy is required in dev."
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on cluster deletion. Defaults to false for prod parity. Set to true only if terraform destroy is required in dev and no snapshot is needed."
  type        = bool
  default     = false
}

variable "elasticache_node_type" {
  description = "ElastiCache node type for Redis clusters (Account and Client). e.g. cache.t3.micro for dev, cache.r6g.large for prod."
  type        = string
  default     = "cache.t3.micro"
}

variable "elasticache_snapshot_retention_days" {
  description = "Number of days to retain automatic ElastiCache Redis snapshots. Aligned with Aurora backup retention baseline."
  type        = number
  default     = 7

  validation {
    condition     = var.elasticache_snapshot_retention_days >= 1
    error_message = "elasticache_snapshot_retention_days must be at least 1."
  }
}

