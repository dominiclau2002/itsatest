output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_1_id" {
  description = "ID of the primary public subnet (AZ-1a)"
  value       = aws_subnet.public_1.id
}

output "public_subnet_2_id" {
  description = "ID of the standby public subnet (AZ-1b)"
  value       = aws_subnet.public_2.id
}

output "private_app_subnet_1_id" {
  description = "ID of the primary private application subnet (AZ-1a)"
  value       = aws_subnet.private_app_1.id
}

output "private_app_subnet_2_id" {
  description = "ID of the standby private application subnet (AZ-1b)"
  value       = aws_subnet.private_app_2.id
}

output "private_db_subnet_1_id" {
  description = "ID of the primary private database subnet (AZ-1a)"
  value       = aws_subnet.private_db_1.id
}

output "private_db_subnet_2_id" {
  description = "ID of the standby private database subnet (AZ-1b)"
  value       = aws_subnet.private_db_2.id
}

output "private_route_table_1_id" {
  description = "ID of the primary private route table"
  value       = aws_route_table.private_primary.id
}

output "private_route_table_2_id" {
  description = "ID of the standby private route table"
  value       = aws_route_table.private_standby.id
}

output "secretsmanager_endpoint_id" {
  description = "VPC endpoint ID for Secrets Manager interface endpoint"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "ecr_dkr_endpoint_id" {
  description = "VPC endpoint ID for ECR DKR interface endpoint"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "ecr_api_endpoint_id" {
  description = "VPC endpoint ID for ECR API interface endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "s3_endpoint_id" {
  description = "VPC endpoint ID for S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3.id
}
