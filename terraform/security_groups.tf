# =============================================================================
# Security Groups - Phase 3
#
# Protects all in-VPC resources: ALB, ECS (Account & Client services),
# RDS Aurora, ElastiCache Redis, and the Secrets Manager PrivateLink endpoint.
#
# Pattern: aws_security_group (base) + aws_security_group_rule (rules).
# No inline ingress/egress blocks - avoids circular dependency issues and
# keeps each rule independently trackable by Terraform state.
#
# Naming convention: "${var.project_name}-${var.environment}-sg-[component]"
# Example:           "itsa-testing-setup-dev-sg-alb"
#
# Out-of-scope (no VPC security group needed):
#   Lambda functions    - both Verification and Logging Lambdas run outside VPC
#   DynamoDB            - accessed via NAT Gateway (VPC endpoint added Phase 3b)
#   SQS / SNS / SES     - AWS-managed, no VPC interface endpoint here
#   S3                  - gateway endpoint requires no SG
#   CloudFront          - global CDN, not in VPC
#   ECR (dkr/api)       - interface endpoints managed by AWS; no custom SG needed
#   Cognito             - SaaS endpoint, no VPC presence
# =============================================================================

# ---------------------------------------------------------------------------
# Data Source: CloudFront Managed Prefix List
#
# Restricts ALB ingress to CloudFront edge nodes only.
# Prevents WAF bypass - if ALB accepted traffic from 0.0.0.0/0, attackers
# could reach the application directly, bypassing CloudFront WAF rules.
# ---------------------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# =============================================================================
# 1. ALB Security Group
#
# Placed in public subnets (public-primary / public-standby).
# Accepts HTTPS (443) from CloudFront managed prefix list only - no direct
# internet access. Forwards to all four ECS task SGs on app_port (8080).
# =============================================================================
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-sg-alb"
  description = "ALB: accept HTTPS from CloudFront prefix list; egress to ECS tasks on app_port"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-alb"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "alb"
  }
}

# Ingress: HTTPS (443) from CloudFront managed prefix list only.
# Reason: Forces all traffic through CloudFront + WAF - no direct internet path to ALB.
resource "aws_security_group_rule" "alb_ingress_https_cloudfront" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from CloudFront edge nodes only - WAF bypass prevention"
}

# Egress: app_port to ECS Account Service - primary tasks (AZ-1a)
resource "aws_security_group_rule" "alb_egress_ecs_account_primary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Account Service primary tasks in AZ-1a"
}

# Egress: app_port to ECS Account Service - secondary tasks (AZ-1b)
resource "aws_security_group_rule" "alb_egress_ecs_account_secondary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Account Service secondary tasks in AZ-1b"
}

# Egress: app_port to ECS Client Service - primary tasks (AZ-1a)
resource "aws_security_group_rule" "alb_egress_ecs_client_primary" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.alb.id
  description              = "Forward requests to Client Service primary tasks in AZ-1a"
}

# Egress: app_port to ECS Client Service - secondary tasks (AZ-1b)
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
#
# Receives routed traffic from the ALB.
# Communicates with: ElastiCache Account (6379), Secrets Manager endpoint (443).
# Reaches DynamoDB, SQS, Cognito, CloudWatch via NAT Gateway (HTTPS 443 internet).
# Account Service has NO access to RDS - it stores account data in DynamoDB only.
# Granting Account→RDS would violate least-privilege (no business justification).
# =============================================================================
resource "aws_security_group" "ecs_account_primary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-account-primary"
  description = "ECS Account Service primary (AZ-1a): ALB ingress; ElastiCache/Secrets/NAT egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-ecs-account-primary"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "ecs-account-primary"
  }
}

# Ingress: app_port from ALB only - no other source may send requests to Account tasks
resource "aws_security_group_rule" "ecs_account_primary_ingress_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Receive application traffic from ALB only"
}

# Egress: app_port back to ALB - stateful return path required for ALB health checks
resource "aws_security_group_rule" "ecs_account_primary_egress_alb" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Stateful return path to ALB (health checks and response routing)"
}

# Egress: Redis (6379) to ElastiCache Account - session and account data caching
resource "aws_security_group_rule" "ecs_account_primary_egress_elasticache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticache_account.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Account Service cache reads/writes - ElastiCache Account cluster"
}

# Egress: HTTPS (443) to Secrets Manager endpoint - retrieve credentials via PrivateLink
# Reason: PrivateLink keeps secret-fetch traffic inside the VPC (no NAT/internet exposure).
resource "aws_security_group_rule" "ecs_account_primary_egress_secretsmanager" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secretsmanager_endpoint.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "Retrieve secrets via Secrets Manager PrivateLink (no internet exposure)"
}

# Egress: HTTPS (443) to internet via NAT - DynamoDB, SQS, Cognito, CloudWatch
# Note: DynamoDB and SQS VPC endpoints will be added in Phase 3b (vpc_endpoints.tf)
#       to eliminate this NAT dependency and improve security posture.
resource "aws_security_group_rule" "ecs_account_primary_egress_nat" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_account_primary.id
  description       = "HTTPS via NAT to DynamoDB, SQS, Cognito, CloudWatch (VPC endpoints pending Phase 3b)"
}

# =============================================================================
# 3. ECS Account Service - Secondary (private-app-2, ap-southeast-1b)
#
# Identical rules to Account Primary - separate SG for AZ-1b tasks.
# Required for HA: ALB routes to both AZs; each AZ needs its own SG.
# =============================================================================
resource "aws_security_group" "ecs_account_secondary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-account-secondary"
  description = "ECS Account Service secondary (AZ-1b): ALB ingress; ElastiCache/Secrets/NAT egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-ecs-account-secondary"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "ecs-account-secondary"
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
  description       = "HTTPS via NAT to DynamoDB, SQS, Cognito, CloudWatch (VPC endpoints pending Phase 3b)"
}

# =============================================================================
# 4. ECS Client Service - Primary (private-app-1, ap-southeast-1a)
#
# Receives routed traffic from the ALB.
# Communicates with: RDS primary (5432), ElastiCache Client (6379),
#   Secrets Manager endpoint (443).
# Reaches SQS, Cognito, CloudWatch via NAT Gateway (HTTPS 443 internet).
# =============================================================================
resource "aws_security_group" "ecs_client_primary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-client-primary"
  description = "ECS Client Service primary (AZ-1a): ALB ingress; RDS/ElastiCache/Secrets/NAT egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-ecs-client-primary"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "ecs-client-primary"
  }
}

# Ingress: app_port from ALB only
resource "aws_security_group_rule" "ecs_client_primary_ingress_alb" {
  type                     = "ingress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Receive application traffic from ALB only"
}

# Egress: app_port back to ALB - stateful return path
resource "aws_security_group_rule" "ecs_client_primary_egress_alb" {
  type                     = "egress"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Stateful return path to ALB (health checks and response routing)"
}

# Egress: PostgreSQL (5432) to RDS primary - client profile reads/writes
resource "aws_security_group_rule" "ecs_client_primary_egress_rds_primary" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds_primary.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "PostgreSQL write queries to Aurora RDS primary writer node"
}

# Egress: Redis (6379) to ElastiCache Client - client profile caching
resource "aws_security_group_rule" "ecs_client_primary_egress_elasticache" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.elasticache_client.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Client Service cache reads/writes - ElastiCache Client cluster"
}

# Egress: HTTPS (443) to Secrets Manager endpoint - retrieve DB credentials via PrivateLink
resource "aws_security_group_rule" "ecs_client_primary_egress_secretsmanager" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.secretsmanager_endpoint.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "Retrieve secrets via Secrets Manager PrivateLink (no internet exposure)"
}

# Egress: HTTPS (443) to internet via NAT - SQS, Cognito, CloudWatch
resource "aws_security_group_rule" "ecs_client_primary_egress_nat" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs_client_primary.id
  description       = "HTTPS via NAT to SQS, Cognito, CloudWatch (VPC endpoints pending Phase 3b)"
}

# =============================================================================
# 5. ECS Client Service - Secondary (private-app-2, ap-southeast-1b)
#
# Identical rules to Client Primary - separate SG for AZ-1b tasks.
# Required for HA: ALB routes to both AZs; each AZ needs its own SG.
# =============================================================================
resource "aws_security_group" "ecs_client_secondary" {
  name        = "${var.project_name}-${var.environment}-sg-ecs-client-secondary"
  description = "ECS Client Service secondary (AZ-1b): ALB ingress; RDS/ElastiCache/Secrets/NAT egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-ecs-client-secondary"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "ecs-client-secondary"
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
  description       = "HTTPS via NAT to SQS, Cognito, CloudWatch (VPC endpoints pending Phase 3b)"
}

# =============================================================================
# 6. RDS Primary Security Group (private-db-1, ap-southeast-1a)
#
# Protects the Aurora PostgreSQL primary writer node.
# ONLY Client Service tasks may connect on port 5432.
# Account Service has NO access - Account reads/writes DynamoDB only.
# Granting Account→RDS access would violate least-privilege with no business reason.
# No egress rules: RDS does not initiate outbound connections.
# =============================================================================
resource "aws_security_group" "rds_primary" {
  name        = "${var.project_name}-${var.environment}-sg-rds-primary"
  description = "RDS Aurora primary writer: PostgreSQL from Client Service only; no egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-rds-primary"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "rds-primary"
  }
}

# Ingress: PostgreSQL (5432) from Client Service primary tasks
resource "aws_security_group_rule" "rds_primary_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.rds_primary.id
  description              = "Client Service primary tasks - read/write client profile records (AZ-1a)"
}

# Ingress: PostgreSQL (5432) from Client Service secondary tasks
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
# 7. RDS Replica Security Group (private-db-2, ap-southeast-1b)
#
# Protects the Aurora PostgreSQL read replica in AZ-1b.
# Purpose: HA and automatic failover only — the replica NEVER receives direct
# application traffic. All four ECS tasks connect exclusively via the Aurora
# cluster endpoint, which Aurora always resolves to the primary instance.
# On primary failure, Aurora promotes the replica and updates the cluster
# endpoint transparently — no application code changes required.
# Read offloading is handled by ElastiCache at the application tier, not here.
#
# The only inbound traffic is Aurora-managed internal replication from the
# primary instance. No ECS task SG is granted access.
# No egress rules: replica does not initiate outbound connections.
# =============================================================================
resource "aws_security_group" "rds_replica" {
  name        = "${var.project_name}-${var.environment}-sg-rds-replica"
  description = "RDS Aurora read replica: Aurora replication from primary only; HA failover; no app traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-rds-replica"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "rds-replica"
  }
}

# Ingress: PostgreSQL (5432) from RDS primary - Aurora-managed internal replication only.
# No ECS task SG is permitted here. Application traffic never targets the replica directly.
resource "aws_security_group_rule" "rds_replica_ingress_rds_primary" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds_primary.id
  security_group_id        = aws_security_group.rds_replica.id
  description              = "Aurora internal replication from primary instance - HA failover only"
}

# =============================================================================
# 8. ElastiCache Account Security Group (private-db-1, ap-southeast-1a)
#
# Protects the Redis cluster serving Account Service.
# ONLY Account Service tasks may connect on port 6379.
# Client Service has no access - separate ElastiCache cluster for isolation.
# No egress rules: ElastiCache does not initiate outbound connections.
# =============================================================================
resource "aws_security_group" "elasticache_account" {
  name        = "${var.project_name}-${var.environment}-sg-elasticache-account"
  description = "ElastiCache Redis for Account Service: Redis from Account ECS tasks only; no egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-elasticache-account"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "elasticache-account"
  }
}

# Ingress: Redis (6379) from Account Service primary tasks
resource "aws_security_group_rule" "elasticache_account_ingress_ecs_account_primary" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.elasticache_account.id
  description              = "Account Service primary tasks - cache reads and writes (AZ-1a)"
}

# Ingress: Redis (6379) from Account Service secondary tasks
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
# 9. ElastiCache Client Security Group (private-db-1, ap-southeast-1a)
#
# Protects the Redis cluster serving Client Service.
# ONLY Client Service tasks may connect on port 6379.
# Account Service has no access - separate cluster maintains service isolation.
# No egress rules: ElastiCache does not initiate outbound connections.
# =============================================================================
resource "aws_security_group" "elasticache_client" {
  name        = "${var.project_name}-${var.environment}-sg-elasticache-client"
  description = "ElastiCache Redis for Client Service: Redis from Client ECS tasks only; no egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-elasticache-client"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "elasticache-client"
  }
}

# Ingress: Redis (6379) from Client Service primary tasks
resource "aws_security_group_rule" "elasticache_client_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.elasticache_client.id
  description              = "Client Service primary tasks - cache reads and writes (AZ-1a)"
}

# Ingress: Redis (6379) from Client Service secondary tasks
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
# 10. Secrets Manager VPC Endpoint Security Group
#
# Protects the interface endpoint ENI for Secrets Manager PrivateLink.
# Accepts HTTPS (443) from all four ECS task SGs - all services fetch credentials.
# No egress rules: AWS manages return traffic internally via PrivateLink.
#
# ECR note: ecr.dkr and ecr.api interface endpoints are managed by AWS and do
#           not require a custom security group resource here.
# Lambda note: both Lambdas run outside the VPC - no SG created for either.
# =============================================================================
resource "aws_security_group" "secretsmanager_endpoint" {
  name        = "${var.project_name}-${var.environment}-sg-secretsmanager-endpoint"
  description = "Secrets Manager PrivateLink endpoint ENI: HTTPS from ECS tasks only; no egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-secretsmanager-endpoint"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "secretsmanager-endpoint"
  }
}

# Ingress: HTTPS (443) from Account Service primary tasks
resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_account_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Account Service primary tasks fetch credentials via PrivateLink (AZ-1a)"
}

# Ingress: HTTPS (443) from Account Service secondary tasks
resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_account_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Account Service secondary tasks fetch credentials via PrivateLink (AZ-1b)"
}

# Ingress: HTTPS (443) from Client Service primary tasks
resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Client Service primary tasks fetch credentials via PrivateLink (AZ-1a)"
}

# Ingress: HTTPS (443) from Client Service secondary tasks
resource "aws_security_group_rule" "secretsmanager_endpoint_ingress_ecs_client_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.secretsmanager_endpoint.id
  description              = "Client Service secondary tasks fetch credentials via PrivateLink (AZ-1b)"
}
