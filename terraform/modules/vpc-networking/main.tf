# =============================================================================
# VPC Networking Module
#
# Contains: VPC, subnets, Internet Gateway, NAT Gateways, route tables,
# and VPC endpoints (Secrets Manager, ECR DKR, ECR API, S3 Gateway).
#
# Security groups for VPC endpoints are managed in the security module.
# Interface endpoints are created WITHOUT security_group_ids here — the
# security module attaches SGs via aws_vpc_endpoint_security_group_association
# to break the circular dependency between vpc-networking and security modules.
# =============================================================================


# =============================================================================
# VPC and Internet Gateway
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}


# =============================================================================
# Subnets
# =============================================================================

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[0] #ALB Primary Public Subnet in ap-southeast-1
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-primary"
  }
}

resource "aws_subnet" "private_app_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[0] #Primary Private Application Subnet in ap-southeast-1
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-primary"
  }
}

resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[0] #Primary Private Database Subnet in ap-southeast-1
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-primary"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[1] # Standby Public Subnet in ap-southeast-1b
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-standby"
  }
}

resource "aws_subnet" "private_app_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[1] # Standby Application Subnet in ap-southeast-1b
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-standby"
  }
}

resource "aws_subnet" "private_db_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[1] # Standby Database Subnet in ap-southeast-1b
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-standby"
  }
}


# =============================================================================
# NAT Gateways and Elastic IPs
# =============================================================================

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_primary" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip-nat-primary"
  }
}

resource "aws_eip" "nat_standby" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip-nat-standby"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "primary" {
  allocation_id = aws_eip.nat_primary.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-primary"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "standby" {
  allocation_id = aws_eip.nat_standby.id
  subnet_id     = aws_subnet.public_2.id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-standby"
  }

  depends_on = [aws_internet_gateway.main]
}


# =============================================================================
# Route Tables
# =============================================================================

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rtb-public"
  }
}

# Private Route Tables
resource "aws_route_table" "private_primary" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.primary.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rtb-private-primary"
  }
}

resource "aws_route_table" "private_standby" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.standby.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rtb-private-standby"
  }
}

# Public Route Table Associations
resource "aws_route_table_association" "public_primary" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_standby" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Associations - Primary AZ
resource "aws_route_table_association" "private_app_primary" {
  subnet_id      = aws_subnet.private_app_1.id
  route_table_id = aws_route_table.private_primary.id
}

resource "aws_route_table_association" "private_db_primary" {
  subnet_id      = aws_subnet.private_db_1.id
  route_table_id = aws_route_table.private_primary.id
}

# Private Route Table Associations - Standby AZ
resource "aws_route_table_association" "private_app_standby" {
  subnet_id      = aws_subnet.private_app_2.id
  route_table_id = aws_route_table.private_standby.id
}

resource "aws_route_table_association" "private_db_standby" {
  subnet_id      = aws_subnet.private_db_2.id
  route_table_id = aws_route_table.private_standby.id
}


# =============================================================================
# VPC Endpoints
#
# Interface endpoints (ENI, PrivateLink):
#   - secretsmanager  : ECS tasks retrieve DB credentials without internet exposure
#   - ecr.dkr         : Fargate pulls image manifests and layers from ECR
#   - ecr.api         : Fargate authenticates image pulls alongside ecr.dkr
#
# Gateway endpoint (route table entry, no ENI):
#   - s3              : ECR stores image layers in S3; required for Fargate image pulls
#
# IMPORTANT: Interface endpoints are created WITHOUT security_group_ids.
# The security module attaches SGs via aws_vpc_endpoint_security_group_association
# to avoid circular dependency (endpoints live here, SGs live in security module).
#
# Out-of-scope (routed via NAT Gateway by architecture decision):
#   - DynamoDB        : NAT path acceptable; VPC endpoint deferred
#   - SQS             : NAT path acceptable; VPC endpoint deferred
#   - CloudWatch Logs : NAT path acceptable; VPC endpoint deferred
# =============================================================================

# Secrets Manager Interface Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  private_dns_enabled = true

  tags = {
    Name      = "${var.project_name}-${var.environment}-vpce-secretsmanager"
    Component = "vpce-secretsmanager"
  }
}

# ECR DKR Interface Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  private_dns_enabled = true

  tags = {
    Name      = "${var.project_name}-${var.environment}-vpce-ecr-dkr"
    Component = "vpce-ecr-dkr"
  }
}

# ECR API Interface Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
  private_dns_enabled = true

  tags = {
    Name      = "${var.project_name}-${var.environment}-vpce-ecr-api"
    Component = "vpce-ecr-api"
  }
}

# S3 Gateway Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_primary.id, aws_route_table.private_standby.id]

  tags = {
    Name      = "${var.project_name}-${var.environment}-vpce-s3"
    Component = "vpce-s3"
  }
}
