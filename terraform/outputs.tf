output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# =============================================================================
# Security Group Outputs — Phase 3
# Exported for use by Phase 4+ resources (VPC endpoints, ECS, RDS, ElastiCache)
# =============================================================================

output "sg_alb_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "sg_ecs_account_primary_id" {
  description = "Security group ID for ECS Account Service primary tasks (AZ-1a)"
  value       = aws_security_group.ecs_account_primary.id
}

output "sg_ecs_account_secondary_id" {
  description = "Security group ID for ECS Account Service secondary tasks (AZ-1b)"
  value       = aws_security_group.ecs_account_secondary.id
}

output "sg_ecs_client_primary_id" {
  description = "Security group ID for ECS Client Service primary tasks (AZ-1a)"
  value       = aws_security_group.ecs_client_primary.id
}

output "sg_ecs_client_secondary_id" {
  description = "Security group ID for ECS Client Service secondary tasks (AZ-1b)"
  value       = aws_security_group.ecs_client_secondary.id
}

output "sg_rds_primary_id" {
  description = "Security group ID for Aurora RDS primary writer node"
  value       = aws_security_group.rds_primary.id
}

output "sg_rds_replica_id" {
  description = "Security group ID for Aurora RDS read replica"
  value       = aws_security_group.rds_replica.id
}

output "sg_elasticache_account_id" {
  description = "Security group ID for ElastiCache Redis cluster serving Account Service"
  value       = aws_security_group.elasticache_account.id
}

output "sg_elasticache_client_id" {
  description = "Security group ID for ElastiCache Redis cluster serving Client Service"
  value       = aws_security_group.elasticache_client.id
}

output "sg_secretsmanager_endpoint_id" {
  description = "Security group ID for the Secrets Manager VPC interface endpoint ENI"
  value       = aws_security_group.secretsmanager_endpoint.id
}

# =============================================================================
# VPC Endpoint Outputs - Phase 3b
# Exported for use by Phase 4+ resources (ECS task definitions, monitoring)
# =============================================================================

output "sg_ecr_endpoint_id" {
  description = "Security group ID for the ECR VPC interface endpoint ENI (shared by ecr.dkr and ecr.api)"
  value       = aws_security_group.ecr_endpoint.id
}

output "vpce_secretsmanager_id" {
  description = "VPC endpoint ID for Secrets Manager interface endpoint"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "vpce_ecr_dkr_id" {
  description = "VPC endpoint ID for ECR DKR interface endpoint (Fargate image manifest and layer pulls)"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpce_ecr_api_id" {
  description = "VPC endpoint ID for ECR API interface endpoint (Fargate image pull authentication)"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpce_s3_id" {
  description = "VPC endpoint ID for S3 gateway endpoint (ECR image layer downloads)"
  value       = aws_vpc_endpoint.s3.id
}
