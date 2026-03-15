# =============================================================================
# Compute Module  -  Outputs
#
# Exposes ECS cluster identifiers, ALB addressing, ECR repository URLs,
# and target group ARNs for downstream use (Phase 9 Route 53 alias records,
# Phase 9 WAF association, Phase 8 EventBridge/SQS integration).
# =============================================================================


# =============================================================================
# ECS Cluster
# =============================================================================

output "ecs_cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}


# =============================================================================
# ALB
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS name for HTTP access"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID for Route 53 alias records (Phase 9)"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ALB ARN for WAF association (Phase 9)"
  value       = aws_lb.main.arn
}

output "alb_listener_arn" {
  description = "HTTP listener ARN (upgrade to HTTPS in Phase 9)"
  value       = aws_lb_listener.http.arn
}


# =============================================================================
# ECR Repositories
# =============================================================================

output "ecr_repo_account_service_url" {
  description = "ECR repository URL for Account Service container images"
  value       = aws_ecr_repository.account_service.repository_url
}

output "ecr_repo_client_service_url" {
  description = "ECR repository URL for Client Service container images"
  value       = aws_ecr_repository.client_service.repository_url
}


# =============================================================================
# Target Groups
# =============================================================================

output "target_group_account_arn" {
  description = "ALB target group ARN for Account Service"
  value       = aws_lb_target_group.account.arn
}

output "target_group_client_arn" {
  description = "ALB target group ARN for Client Service"
  value       = aws_lb_target_group.client.arn
}

output "alb_https_listener_arn" {
  description = "HTTPS listener ARN  -  null when no custom domain configured; used by cdn module for certificate association"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}


# =============================================================================
# Phase 10  -  Monitoring Module Inputs
# =============================================================================

output "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/name/abc123)  -  required as CloudWatch metric dimension; CloudWatch rejects the full ARN"
  value       = aws_lb.main.arn_suffix
}

output "ecs_account_primary_service_name" {
  description = "Account Service primary ECS service name  -  used as CloudWatch alarm ServiceName dimension"
  value       = aws_ecs_service.account_primary.name
}

output "ecs_client_primary_service_name" {
  description = "Client Service primary ECS service name  -  used as CloudWatch alarm ServiceName dimension"
  value       = aws_ecs_service.client_primary.name
}
