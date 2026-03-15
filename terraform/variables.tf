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
  description = "Number of days to retain RDS automated backups. 0 disables automated backups (free tier). Minimum 7 for dev, 30 for prod."
  type        = number
  default     = 7

  validation {
    condition     = var.rds_backup_retention_days >= 0 && var.rds_backup_retention_days <= 35
    error_message = "rds_backup_retention_days must be between 0 (disabled) and 35."
  }
}

variable "rds_database_name" {
  description = "Name of the initial PostgreSQL database created on the Aurora cluster"
  type        = string
  default     = "crmdb"
}

variable "create_rds_cluster" {
  description = "Set to false to skip Aurora cluster creation on free-tier AWS accounts (Aurora requires WithExpressConfiguration on free tier). Set true once account is upgraded."
  type        = bool
  default     = true
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

# =============================================================================
# Phase 6: Authentication Variables
# =============================================================================

variable "cognito_domain_prefix" {
  description = "Cognito hosted UI domain prefix (must be globally unique across all AWS accounts). Defaults to project_name-environment."
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

# =============================================================================
# Phase 7: Compute & Application Tier Variables
# =============================================================================

variable "ecs_task_cpu" {
  description = "CPU units for ECS Fargate tasks (256 = 0.25 vCPU). Override in tfvars for prod."
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Memory in MiB for ECS Fargate tasks. Must be compatible with cpu value."
  type        = number
  default     = 512
}

variable "container_image_account" {
  description = "Container image URI for Account Service. Placeholder until real images are pushed to ECR."
  type        = string
  default     = "public.ecr.aws/docker/library/httpd:2.4"
}

variable "container_image_client" {
  description = "Container image URI for Client Service. Placeholder until real images are pushed to ECR."
  type        = string
  default     = "public.ecr.aws/docker/library/httpd:2.4"
}

variable "health_check_path" {
  description = "Health check path for ALB target groups"
  type        = string
  default     = "/health"
}

variable "ecs_log_retention_days" {
  description = "CloudWatch log retention in days for ECS container logs"
  type        = number
  default     = 365 # CKV_AWS_338: minimum 1 year for compliance
}

variable "alb_deletion_protection" {
  description = "Enable ALB deletion protection. Default false for dev; set true for prod via tfvars."
  type        = bool
  default     = false
}

# =============================================================================
# Phase 8: Event-Driven Architecture Variables
# =============================================================================

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention in days for Lambda function logs"
  type        = number
  default     = 365 # CKV_AWS_338: minimum 1 year for compliance
}

variable "sftp_schedule_expression" {
  description = "EventBridge schedule expression for SFTP fetch trigger (e.g. rate(1 hour), cron(0 * * * ? *))"
  type        = string
  default     = "rate(1 hour)"
}

# =============================================================================
# Phase 9: Frontend & CDN Variables
# =============================================================================

variable "domain_name" {
  description = "Custom domain name for CloudFront and ALB (e.g. crm.example.com). Empty string (default) skips HTTPS listeners, ACM certs, and Route 53 records  -  CDN uses CloudFront default certificate."
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class controlling which edge locations serve content. PriceClass_All = global coverage (default); PriceClass_200 = excludes South America and Australia; PriceClass_100 = North America and Europe only."
  type        = string
  default     = "PriceClass_All"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}


# =============================================================================
# Phase 10: Monitoring Variables
# =============================================================================

variable "alarm_email" {
  description = "Email address for CloudWatch alarm SNS notifications. Empty string (default) disables email subscription  -  alarms still fire to SNS topic."
  type        = string
  default     = ""
}

# =============================================================================
# Multi-Environment Variables
# =============================================================================

variable "cost_center" {
  description = "Cost center tag for billing allocation"
  type        = string
  default     = "CS301"
}

variable "created_date" {
  description = "Project creation date tag (YYYY-MM-DD)"
  type        = string
  default     = "2026-02-21"
}

variable "dynamodb_deletion_protection" {
  description = "Enable deletion protection on all DynamoDB tables. Set true for prod."
  type        = bool
  default     = true
}

variable "ecs_min_capacity" {
  description = "Minimum ECS service count for auto-scaling (per service)"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum ECS service count for auto-scaling (per service)"
  type        = number
  default     = 3
}

