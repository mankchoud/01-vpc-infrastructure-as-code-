###############################################################################
# flow_logs.tf — VPC Flow Logs
#
# Flow logs capture metadata on every network packet in the VPC:
#   source IP, destination IP, port, protocol, bytes, action (ACCEPT/REJECT)
#
# They do NOT capture packet contents — only metadata.
# Use them to: detect port scans, trace rejected traffic, audit access patterns.
#
# TWO DESTINATIONS (both configured here):
#
#   CloudWatch Logs — for real-time alerting and Logs Insights queries
#   S3             — for cheap long-term retention and bulk analysis
#
# FREE-TIER COST CONSIDERATIONS:
#   CloudWatch Logs ingestion: first 5GB/month free, then $0.50/GB
#   S3 storage: first 5GB/month free
#   → Keep retention short (7 days default) and filter to REJECT only
#     if you hit the free tier limit. ALL traffic is configured here
#     for maximum learning value.
#
# PRODUCTION SUBSTITUTE FOR ATHENA:
#   The project spec mentions Athena for S3 log analysis ($5/TB scanned).
#   Free-tier alternative: CloudWatch Logs Insights (included with log storage).
#   Use the sample queries in docs/security-decisions.md.
###############################################################################

###############################################################################
# CloudWatch Log Group for Flow Logs
###############################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/flow-logs/${var.project_name}"
  retention_in_days = var.flow_log_retention_days  # Default 7 days — keep costs low

  tags = {
    Name = "${var.project_name}-flow-logs"
  }
}

###############################################################################
# IAM Role — allows VPC Flow Logs service to write to CloudWatch
###############################################################################

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

###############################################################################
# VPC Flow Log → CloudWatch
# Captures ALL traffic (ACCEPT + REJECT) for full visibility.
# To reduce cost: change traffic_type = "REJECT" (only captures blocked traffic)
###############################################################################

resource "aws_flow_log" "cloudwatch" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"   # Change to "REJECT" to reduce CloudWatch ingestion cost
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name        = "${var.project_name}-flow-log-cloudwatch"
    Destination = "cloudwatch"
  }
}

###############################################################################
# S3 Bucket for Flow Log Archive
###############################################################################

resource "aws_s3_bucket" "flow_logs" {
  # Bucket names must be globally unique — suffix with account ID
  bucket        = "${var.project_name}-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true  # Allows terraform destroy to delete even non-empty bucket

  tags = {
    Name    = "${var.project_name}-flow-logs"
    Purpose = "VPC Flow Log archive"
  }
}

# Block all public access — flow logs contain sensitive network data
resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # SSE-S3 — free. SSE-KMS costs ~$1/10k requests.
    }
  }
}

# Lifecycle: expire logs after 30 days to stay within S3 free tier
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    # filter is required in AWS provider v5 — empty applies rule to all objects
    filter {}

    expiration {
      days = 30
    }
  }
}

###############################################################################
# VPC Flow Log → S3
###############################################################################

resource "aws_flow_log" "s3" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn

  tags = {
    Name        = "${var.project_name}-flow-log-s3"
    Destination = "s3"
  }

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}
