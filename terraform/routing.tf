###############################################################################
# routing.tf — Route Tables and Associations
#
# Three separate route tables:
#   1. Public  — 0.0.0.0/0 → Internet Gateway
#   2. Private — 0.0.0.0/0 → NAT Instance (outbound only)
#   3. Data    — local only (NO default route — fully isolated)
###############################################################################

###############################################################################
# PUBLIC ROUTE TABLE
# All traffic not destined for the VPC CIDR exits via the Internet Gateway.
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# PRIVATE ROUTE TABLE
# Outbound internet traffic goes to the NAT Instance in the public subnet.
# The NAT Instance rewrites the source IP and forwards via the IGW.
#
# PRODUCTION NOTE: In production you would have one route table per AZ,
# each pointing to that AZ's dedicated NAT Gateway for resilience.
###############################################################################

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "${var.project_name}-rt-private"
    # Document HA caveat for portfolio reviewers
    Note = "Single NAT Instance — production would use per-AZ NAT Gateways"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# DATA ROUTE TABLE
# NO default route — data subnet instances cannot reach the internet at all.
# AWS services (S3, DynamoDB) are accessible via VPC Gateway Endpoints (free).
###############################################################################

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  # Intentionally no 0.0.0.0/0 route — this is the security control.
  # The only traffic allowed is within the VPC CIDR (local) and
  # to AWS services via the Gateway Endpoints added in endpoints.tf.

  tags = {
    Name = "${var.project_name}-rt-data"
    Note = "No internet route — data tier is fully isolated"
  }
}

resource "aws_route_table_association" "data" {
  count = length(aws_subnet.data)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}
