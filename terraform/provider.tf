terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.profile

  # Default tags to apply to all resources
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
      CostCenter  = "CS301"
      CreatedDate = "2026-02-21"
    }
  }
}
