variable "vpc_id" {
  description = "ID of the VPC for security group placement"
  type        = string
}

variable "app_port" {
  description = "Port that ECS application containers listen on"
  type        = number
}

variable "aws_region" {
  description = "AWS region for ARN construction"
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

variable "secretsmanager_endpoint_id" {
  description = "VPC endpoint ID for Secrets Manager — used for SG association"
  type        = string
}

variable "ecr_dkr_endpoint_id" {
  description = "VPC endpoint ID for ECR DKR — used for SG association"
  type        = string
}

variable "ecr_api_endpoint_id" {
  description = "VPC endpoint ID for ECR API — used for SG association"
  type        = string
}
