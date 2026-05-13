###############################################################################
# nacls.tf — Network ACLs (Subnet-Level Stateless Controls)
#
# NACLs are the second layer of defence (security groups are the first).
# Key difference from SGs: NACLs are STATELESS — return traffic must be
# explicitly allowed. Ephemeral ports (1024-65535) must be open for responses.
#
# Rule numbers matter — evaluated lowest first. Use gaps (100, 200, 300)
# so you can insert rules later without renumbering.
###############################################################################

###############################################################################
# PUBLIC SUBNET NACL
# Allows inbound HTTP/HTTPS from internet + ephemeral return ports.
###############################################################################

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  ###########################################################################
  # INBOUND RULES
  ###########################################################################

  # Allow HTTPS from internet
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow HTTP from internet (for redirect to HTTPS)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow ephemeral ports (return traffic from internet responses)
  # NACLs are stateless — outbound requests from private/public subnets
  # return on these ports. Without this, responses are dropped.
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all inbound from within the VPC (inter-subnet communication)
  ingress {
    rule_no    = 130
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  ###########################################################################
  # OUTBOUND RULES
  ###########################################################################

  # Allow all outbound (internet + VPC)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-nacl-public"
  }
}

###############################################################################
# PRIVATE SUBNET NACL (App Tier)
# Only accepts traffic from the public subnet (Nginx) and VPC-internal.
# Outbound goes to internet via NAT (allow all) and to data subnet.
###############################################################################

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.private[*].id

  ###########################################################################
  # INBOUND RULES
  ###########################################################################

  # Allow traffic from public subnets (Nginx → App on port 8080)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.public_subnet_cidrs[0]
    from_port  = 8080
    to_port    = 8080
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.public_subnet_cidrs[1]
    from_port  = 8080
    to_port    = 8080
  }

  # Allow ephemeral ports for return traffic (responses from internet via NAT)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Deny all other inbound (explicit deny — belt and braces with SGs)
  ingress {
    rule_no    = 32766
    protocol   = "-1"
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ###########################################################################
  # OUTBOUND RULES
  ###########################################################################

  # Allow all outbound (NAT Instance forwards to internet, also to data tier)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-nacl-private"
  }
}

###############################################################################
# DATA SUBNET NACL
# Only accepts traffic from private subnets on the DB port.
# Outbound is restricted to VPC-only (no internet route anyway,
# but defence in depth means we enforce it at the NACL level too).
###############################################################################

resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.data[*].id

  ###########################################################################
  # INBOUND RULES
  ###########################################################################

  # Allow PostgreSQL (5432) from private subnets only
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.private_subnet_cidrs[0]
    from_port  = 5432
    to_port    = 5432
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.private_subnet_cidrs[1]
    from_port  = 5432
    to_port    = 5432
  }

  # Allow ephemeral ports for DB response traffic back to app servers
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  # Deny everything else — including any public subnet traffic
  ingress {
    rule_no    = 32766
    protocol   = "-1"
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ###########################################################################
  # OUTBOUND RULES
  ###########################################################################

  # Only allow outbound to VPC CIDR (responses to app servers)
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Deny all other outbound (belt and braces — no internet route exists anyway)
  egress {
    rule_no    = 32766
    protocol   = "-1"
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-nacl-data"
  }
}
