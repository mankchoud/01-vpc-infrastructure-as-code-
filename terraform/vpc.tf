###############################################################################
# vpc.tf — VPC, Subnets, Internet Gateway
###############################################################################

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # Required for VPC endpoints
  enable_dns_hostnames = true   # Required for VPC endpoints

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

###############################################################################
# Internet Gateway — allows public subnets to reach the internet
# Cost: FREE
###############################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

###############################################################################
# PUBLIC SUBNETS
# Resources here: Nginx EC2 (replaces ALB), NAT Instance (replaces NAT GW)
# Internet access: direct via IGW
###############################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true  # Instances here get a public IP automatically

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  }
}

###############################################################################
# PRIVATE SUBNETS (App Tier)
# Resources here: App EC2 instances
# Internet access: outbound only via NAT Instance
###############################################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false  # No public IPs — private subnet

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  }
}

###############################################################################
# DATA SUBNETS (Database Tier)
# Resources here: Databases / sensitive data stores
# Internet access: NONE — no default route at all
#
# FREE-TIER NOTE: RDS costs money, so no RDS instance is created here.
# The subnets, security groups, and route tables are created to demonstrate
# the correct isolation design. In production, an RDS instance would live here.
###############################################################################

resource "aws_subnet" "data" {
  count = length(var.data_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.data_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-data-${count.index + 1}"
    Tier = "data"
  }
}
