###############################################################################
# main.tf — Provider & Backend Configuration
#
# FREE-TIER NOTE: Backend is local (no S3 + DynamoDB state locking, which
# costs money). In production you would use:
#   backend "s3" { bucket = "..." dynamodb_table = "..." }
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # LOCAL backend — free tier safe.
  # Production substitute: S3 + DynamoDB locking.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "cloud-security-project-2"
      Environment = var.environment
      ManagedBy   = "terraform"
      CostCenter  = "free-tier-learning"
    }
  }
}

###############################################################################
# Data sources
###############################################################################

# Fetch the 2 first available AZs in the chosen region
data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2 AMI — used for both NAT instance and app servers
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
