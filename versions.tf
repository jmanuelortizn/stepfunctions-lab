terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Lab uses local state. In production: S3 backend + DynamoDB locking
  # (or S3 native locking with use_lockfile in TF >= 1.10).
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Purpose   = "stepfunctions-lab"
    }
  }
  profile = var.aws_profile
}
