terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    # random: generates the RDS master password and Redis AUTH tokens.
    # These are created once and stored in Secrets Manager — not regenerated on each apply.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # archive: zips placeholder Lambda handler code for deployment packages (Phase 8).
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Remote state backend — S3 bucket and DynamoDB lock table must be bootstrapped
  # via AWS CLI before running `terraform init`. See CLAUDE.md Commands section
  # for the bootstrap commands.
  backend "s3" {
    bucket         = "itsa-testing-setup-dev-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "itsa-testing-setup-dev-terraform-lock"
    encrypt        = true
    profile        = "dominic-admin"
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
