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

resource "aws_subnet" "public_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[0] #ALB Primary Public Subnet in ap-southeast-1
  availability_zone = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-primary"
  }
}

resource "aws_subnet" "private_app_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_app_subnet_cidrs[0] #Primary Private Application Subnet in ap-southeast-1
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-primary"
  }
}

resource "aws_subnet" "private_db_1" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_db_subnet_cidrs[0] #Primary Private Database Subnet in ap-southeast-1
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-primary"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[1] # Standby Public Subnet in ap-southeast-1b
  availability_zone = var.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-standby"
  }
}

resource "aws_subnet" "private_app_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_app_subnet_cidrs[1] # Standby Application Subnet in ap-southeast-1b
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-standby"
  }
}

resource "aws_subnet" "private_db_2" {
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_db_subnet_cidrs[1] # Standby Database Subnet in ap-southeast-1b
  availability_zone = var.availability_zones[1]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-standby"
  }
}