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
