# =============================================================================
# VPC Endpoints - Phase 3b
#
# Provides private AWS service access for ECS tasks running in private-app subnets.
# Eliminates the need for those services to route via NAT Gateway.
#
# Interface endpoints (ENI, PrivateLink):
#   - secretsmanager  : ECS tasks retrieve DB credentials without internet exposure
#   - ecr.dkr         : Fargate pulls image manifests and layers from ECR
#   - ecr.api         : Fargate authenticates image pulls alongside ecr.dkr
#
# Gateway endpoint (route table entry, no ENI):
#   - s3              : ECR stores image layers in S3; required for Fargate image pulls
#
# Out-of-scope (routed via NAT Gateway by architecture decision):
#   - DynamoDB        : NAT path acceptable; VPC endpoint deferred
#   - SQS             : NAT path acceptable; VPC endpoint deferred
#   - CloudWatch Logs : NAT path acceptable; VPC endpoint deferred
#
# Naming convention: "${var.project_name}-${var.environment}-vpce-[service]"
# Example:           "itsa-testing-setup-dev-vpce-secretsmanager"
# =============================================================================

# =============================================================================
# 1. ECR Endpoint Security Group
#
# Shared by ecr.dkr and ecr.api interface endpoints.
# Both endpoints require identical access (HTTPS 443 from all ECS task SGs).
# No egress rules: AWS manages return traffic internally via PrivateLink.
# =============================================================================
resource "aws_security_group" "ecr_endpoint" {
  name        = "${var.project_name}-${var.environment}-sg-ecr-endpoint"
  description = "ECR PrivateLink endpoint ENI: HTTPS from ECS tasks only; no egress"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-ecr-endpoint"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "ecr-endpoint"
  }
}

# Ingress: HTTPS (443) from Account Service primary tasks
# Reason: Account Service primary tasks (AZ-1a) pull container image from ECR via PrivateLink
resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_account_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_primary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Account Service primary tasks pull container image from ECR (AZ-1a)"
}

# Ingress: HTTPS (443) from Account Service secondary tasks
# Reason: Account Service secondary tasks (AZ-1b) pull container image from ECR via PrivateLink
resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_account_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_account_secondary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Account Service secondary tasks pull container image from ECR (AZ-1b)"
}

# Ingress: HTTPS (443) from Client Service primary tasks
# Reason: Client Service primary tasks (AZ-1a) pull container image from ECR via PrivateLink
resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_client_primary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_primary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Client Service primary tasks pull container image from ECR (AZ-1a)"
}

# Ingress: HTTPS (443) from Client Service secondary tasks
# Reason: Client Service secondary tasks (AZ-1b) pull container image from ECR via PrivateLink
resource "aws_security_group_rule" "ecr_endpoint_ingress_ecs_client_secondary" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_client_secondary.id
  security_group_id        = aws_security_group.ecr_endpoint.id
  description              = "Client Service secondary tasks pull container image from ECR (AZ-1b)"
}

# =============================================================================
# 2. ECS Egress Rules to ECR Endpoint
#
# Each of the four ECS task SGs requires one explicit egress rule to reach the
# ecr_endpoint SG over HTTPS (443) for container image pulls.
# Secrets Manager egress rules already exist in security_groups.tf (Phase 3).
# =============================================================================

# Egress: Account Service primary to ECR endpoint
resource "aws_security_group_rule" "ecs_account_primary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_account_primary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

# Egress: Account Service secondary to ECR endpoint
resource "aws_security_group_rule" "ecs_account_secondary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_account_secondary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

# Egress: Client Service primary to ECR endpoint
resource "aws_security_group_rule" "ecs_client_primary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_client_primary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

# Egress: Client Service secondary to ECR endpoint
resource "aws_security_group_rule" "ecs_client_secondary_egress_ecr" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecr_endpoint.id
  security_group_id        = aws_security_group.ecs_client_secondary.id
  description              = "ECR image pulls via PrivateLink (ecr.dkr and ecr.api endpoints)"
}

# =============================================================================
# 3. Secrets Manager Interface Endpoint
#
# Places an ENI in each private-app subnet so ECS tasks retrieve credentials
# via PrivateLink without leaving the VPC (no NAT Gateway required).
# private_dns_enabled resolves secretsmanager.ap-southeast-1.amazonaws.com
# to the private ENI IP automatically.
# =============================================================================
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  security_group_ids  = [aws_security_group.secretsmanager_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpce-secretsmanager"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "vpce-secretsmanager"
  }
}

# =============================================================================
# 4. ECR DKR Interface Endpoint
#
# Fargate uses ecr.dkr to pull image manifests and layer blobs from ECR.
# Both ecr.dkr and ecr.api must be present for Fargate image pulls to succeed.
# private_dns_enabled resolves *.dkr.ecr.ap-southeast-1.amazonaws.com to
# private ENI IPs automatically.
# =============================================================================
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  security_group_ids  = [aws_security_group.ecr_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpce-ecr-dkr"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "vpce-ecr-dkr"
  }
}

# =============================================================================
# 5. ECR API Interface Endpoint
#
# Fargate requires ecr.api alongside ecr.dkr to authenticate image pulls.
# Both endpoints share the ecr_endpoint SG - identical HTTPS 443 requirements.
# private_dns_enabled resolves api.ecr.ap-southeast-1.amazonaws.com to
# private ENI IPs automatically.
# =============================================================================
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  security_group_ids  = [aws_security_group.ecr_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpce-ecr-api"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "vpce-ecr-api"
  }
}

# =============================================================================
# 6. S3 Gateway Endpoint
#
# ECR stores image layers in S3. Fargate cannot pull images from ECR without
# this gateway endpoint, even when ecr.dkr and ecr.api endpoints are present.
# Gateway type: adds a route entry to the specified route tables; no ENI or SG.
# Both private route tables included so tasks in AZ-1a and AZ-1b can reach S3.
# =============================================================================
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_primary.id, aws_route_table.private_standby.id]

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpce-s3"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "vpce-s3"
  }
}
