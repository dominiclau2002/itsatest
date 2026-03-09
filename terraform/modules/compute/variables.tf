# =============================================================================
# Compute Module — Input Variables
#
# All values received from the root module. No defaults for infrastructure
# identifiers — they must always be explicitly supplied.
# Defaults provided only for tunable operational parameters.
# =============================================================================


# =============================================================================
# Core Identity
# =============================================================================

variable "aws_region" {
  description = "AWS region for resource placement"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "app_port" {
  description = "Port that ECS application containers listen on"
  type        = number
}


# =============================================================================
# Networking
# =============================================================================

variable "vpc_id" {
  description = "VPC ID for ALB and target groups"
  type        = string
}

variable "public_subnet_1_id" {
  description = "Public subnet 1 ID (AZ-1a) for ALB placement"
  type        = string
}

variable "public_subnet_2_id" {
  description = "Public subnet 2 ID (AZ-1b) for ALB placement"
  type        = string
}

variable "private_app_subnet_1_id" {
  description = "Private application subnet 1 ID (AZ-1a) for ECS tasks"
  type        = string
}

variable "private_app_subnet_2_id" {
  description = "Private application subnet 2 ID (AZ-1b) for ECS tasks"
  type        = string
}


# =============================================================================
# Security Groups
# =============================================================================

variable "sg_alb_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "sg_ecs_account_primary_id" {
  description = "Security group ID for ECS Account Service primary tasks (AZ-1a)"
  type        = string
}

variable "sg_ecs_account_secondary_id" {
  description = "Security group ID for ECS Account Service secondary tasks (AZ-1b)"
  type        = string
}

variable "sg_ecs_client_primary_id" {
  description = "Security group ID for ECS Client Service primary tasks (AZ-1a)"
  type        = string
}

variable "sg_ecs_client_secondary_id" {
  description = "Security group ID for ECS Client Service secondary tasks (AZ-1b)"
  type        = string
}


# =============================================================================
# IAM Roles
# =============================================================================

variable "iam_role_ecs_account_execution_arn" {
  description = "ARN of the ECS task execution role for Account Service"
  type        = string
}

variable "iam_role_ecs_account_task_arn" {
  description = "ARN of the ECS task role for Account Service"
  type        = string
}

variable "iam_role_ecs_client_execution_arn" {
  description = "ARN of the ECS task execution role for Client Service"
  type        = string
}

variable "iam_role_ecs_client_task_arn" {
  description = "ARN of the ECS task role for Client Service"
  type        = string
}


# =============================================================================
# Data Layer — RDS
# =============================================================================

variable "rds_cluster_endpoint" {
  description = "Aurora cluster writer endpoint for Client Service"
  type        = string
}

variable "rds_cluster_port" {
  description = "Aurora cluster port (5432)"
  type        = number
}

variable "rds_database_name" {
  description = "Name of the initial database on the Aurora cluster"
  type        = string
}

variable "rds_master_username" {
  description = "Aurora master username (single source of truth from data-layer)"
  type        = string
}


# =============================================================================
# Data Layer — DynamoDB
# =============================================================================

variable "dynamodb_table_accounts_name" {
  description = "DynamoDB Accounts table name for Account Service"
  type        = string
}

variable "dynamodb_table_transactions_name" {
  description = "DynamoDB Transactions table name for Account Service"
  type        = string
}


# =============================================================================
# Data Layer — ElastiCache
# =============================================================================

variable "elasticache_account_endpoint" {
  description = "Account Redis primary endpoint address"
  type        = string
}

variable "elasticache_account_port" {
  description = "Account Redis port"
  type        = number
}

variable "elasticache_client_endpoint" {
  description = "Client Redis primary endpoint address"
  type        = string
}

variable "elasticache_client_port" {
  description = "Client Redis port"
  type        = number
}


# =============================================================================
# Secrets Manager ARNs
# =============================================================================

variable "secret_rds_master_password_arn" {
  description = "Secrets Manager ARN for RDS master password (injected into Client Service)"
  type        = string
}

variable "secret_redis_account_auth_arn" {
  description = "Secrets Manager ARN for Account Redis AUTH token"
  type        = string
}

variable "secret_redis_client_auth_arn" {
  description = "Secrets Manager ARN for Client Redis AUTH token"
  type        = string
}


# =============================================================================
# Auth
# =============================================================================

variable "cognito_user_pool_id" {
  description = "Cognito user pool ID for JWKS URL construction"
  type        = string
}


# =============================================================================
# Tunable Operational Parameters (defaults suitable for dev)
# =============================================================================

variable "ecs_task_cpu" {
  description = "CPU units for ECS Fargate tasks (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Memory in MiB for ECS Fargate tasks"
  type        = number
  default     = 512
}

variable "container_image_account" {
  description = "Container image URI for Account Service (placeholder until real images pushed to ECR)"
  type        = string
  default     = "public.ecr.aws/docker/library/httpd:2.4"
}

variable "container_image_client" {
  description = "Container image URI for Client Service (placeholder until real images pushed to ECR)"
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
  default     = 30
}

variable "alb_deletion_protection" {
  description = "Enable ALB deletion protection (set true for prod via tfvars)"
  type        = bool
  default     = false
}

# =============================================================================
# Phase 8 — SQS Queue URL
# =============================================================================

variable "sqs_queue_logging_url" {
  description = "SQS Logging queue URL — injected into ECS task definitions for audit event publishing"
  type        = string
}

# =============================================================================
# Phase 9 — Domain & HTTPS
# =============================================================================

variable "domain_name" {
  description = "Custom domain name (e.g. crm.example.com). Empty string keeps HTTP-only listener with 404 default. When set, HTTP listener redirects to HTTPS and a separate HTTPS listener is created."
  type        = string
  default     = ""
}

variable "acm_cert_alb_arn" {
  description = "ACM certificate ARN (ap-southeast-1) for the ALB HTTPS listener. Required when domain_name is set. Empty string skips HTTPS listener creation."
  type        = string
  default     = ""
}


# =============================================================================
# Phase 9 — Lambda ALB Routing
# =============================================================================

variable "lambda_verification_arn" {
  description = "Verification Lambda function ARN — registered as ALB Lambda target group target (path /api/clients/*/verify, priority 150)"
  type        = string
}

variable "lambda_user_arn" {
  description = "User Lambda function ARN — registered as ALB Lambda target group target (path /api/users/*, priority 300)"
  type        = string
}


# =============================================================================
# Phase 10 — ECS Auto Scaling Bounds
# =============================================================================

variable "ecs_min_capacity" {
  description = "Minimum ECS service task count per AZ service instance for auto-scaling (floor when scaling in)"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum ECS service task count per AZ service instance for auto-scaling (ceiling when scaling out)"
  type        = number
  default     = 3
}
