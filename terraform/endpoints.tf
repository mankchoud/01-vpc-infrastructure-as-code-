###############################################################################
# endpoints.tf — VPC Endpoints
#
# VPC Endpoints let resources in private/data subnets reach AWS services
# without traffic leaving the AWS network (no NAT required, more secure).
#
# TWO TYPES — only Gateway type is free:
#
#   GATEWAY ENDPOINTS (FREE ✅)
#   ─────────────────────────────
#   Supported services: S3, DynamoDB only
#   How it works: adds a route to your route table pointing to the endpoint
#   Cost: $0
#
#   INTERFACE ENDPOINTS (COSTLY ❌ — ~$7/mo each)
#   ──────────────────────────────────────────────
#   Supported services: SSM, EC2, ECR, KMS, Secrets Manager, etc.
#   How it works: creates an ENI with a private IP in your subnet
#   Cost: ~$0.01/hr + data charges per endpoint
#
# FREE-TIER DECISION: Create Gateway Endpoints for S3 + DynamoDB only.
# Interface endpoints are skipped — document what they would be in production.
#
# PRODUCTION ENDPOINTS TO ADD (not created here):
#   - com.amazonaws.<region>.ssm           (SSM Session Manager)
#   - com.amazonaws.<region>.ssmmessages   (SSM Session Manager)
#   - com.amazonaws.<region>.ec2messages   (SSM Session Manager)
#   - com.amazonaws.<region>.ecr.api       (ECR — pull container images)
#   - com.amazonaws.<region>.ecr.dkr       (ECR — Docker registry)
#   - com.amazonaws.<region>.kms           (KMS encryption)
#   - com.amazonaws.<region>.logs          (CloudWatch Logs)
#   - com.amazonaws.<region>.secretsmanager (Secrets Manager)
###############################################################################

###############################################################################
# S3 Gateway Endpoint — FREE
# Allows private/data subnets to read/write S3 without going via the internet.
# Essential for: application logs, artifacts, backups, data exports.
###############################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"  # Gateway type = free

  # Associate with all route tables so all subnet tiers can reach S3
  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id,
    aws_route_table.data.id,
  ]

  # Endpoint policy — restrict to your own account's buckets only
  # This prevents a compromised instance from exfiltrating data to
  # an attacker-controlled S3 bucket.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowS3AccessFromVPC"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-endpoint-s3"
    Type = "Gateway"
    Cost = "Free"
  }
}

###############################################################################
# DynamoDB Gateway Endpoint — FREE
# Useful if your application uses DynamoDB for sessions, state, etc.
###############################################################################

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id,
    aws_route_table.data.id,
  ]

  tags = {
    Name = "${var.project_name}-endpoint-dynamodb"
    Type = "Gateway"
    Cost = "Free"
  }
}

###############################################################################
# Data source for current AWS account ID (used in endpoint policy)
###############################################################################

data "aws_caller_identity" "current" {}
