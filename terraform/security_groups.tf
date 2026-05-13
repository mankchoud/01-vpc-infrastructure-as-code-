###############################################################################
# security_groups.tf — Security Groups
#
# Design principle: chain SG references, not CIDR blocks.
# Each tier only accepts traffic from the tier directly upstream.
#
#   nginx-sg  →  app-sg  →  db-sg
#
# This mirrors the original ALB-SG → App-SG → DB-SG chain from the project spec.
# Replacing ALB-SG with nginx-sg is a drop-in substitution — same concept.
###############################################################################

###############################################################################
# NAT Instance Security Group
# Allows outbound traffic from private subnets to reach the internet.
###############################################################################

resource "aws_security_group" "nat" {
  name        = "${var.project_name}-nat-sg"
  description = "NAT Instance - allows private subnet outbound internet traffic"
  vpc_id      = aws_vpc.main.id

  # Accept traffic from private subnets (the instances that need NAT)
  ingress {
    description = "All traffic from private subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnet_cidrs
  }

  # Also accept traffic from data subnets (for VPC endpoint traffic if needed)
  ingress {
    description = "All traffic from data subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.data_subnet_cidrs
  }

  # Full outbound to internet — NAT needs to forward packets
  egress {
    description = "All outbound - NAT forwards to internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nat-sg"
  }
}

###############################################################################
# Nginx Security Group (Free-tier substitute for ALB)
#
# PRODUCTION EQUIVALENT: ALB Security Group
#   - Accepts HTTPS (443) from internet
#   - In production: also HTTP (80) to redirect to HTTPS
#
# FREE-TIER: Also accepts HTTP (80) since we don't have an ACM cert.
#   For a real portfolio piece you can get a free cert via ACM + Route53,
#   but that requires a domain name.
###############################################################################

resource "aws_security_group" "nginx" {
  name        = "${var.project_name}-nginx-sg"
  description = "Nginx reverse proxy - public-facing entry point (replaces ALB)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS in production)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                 = "${var.project_name}-nginx-sg"
    ProductionEquivalent = "ALB Security Group"
  }
}

###############################################################################
# App Server Security Group
# Only accepts traffic from the Nginx SG — not from the internet directly.
# This is the key isolation: app servers are invisible to the internet.
###############################################################################

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "App servers - only reachable from Nginx SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from Nginx only (port 8080)"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]  # SG reference, not CIDR
  }

  egress {
    description = "All outbound (goes via NAT Instance to internet)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

###############################################################################
# Database Security Group
# Only accepts traffic from the App SG — not from Nginx or internet.
# Port 5432 = PostgreSQL. Change to 3306 for MySQL.
###############################################################################

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Database tier - only reachable from App SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from App SG only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]  # SG reference, not CIDR
  }

  # No egress to internet — data subnet has no route anyway,
  # but defence-in-depth means we restrict it at the SG level too.
  egress {
    description = "VPC-local only (to App SG for responses)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

###############################################################################
# App EC2 Instance — free-tier t2.micro in private subnet
#
# PRODUCTION NOTE: This would be an Auto Scaling Group with a Launch Template,
# not a single instance. For learning purposes a single instance demonstrates
# the security group chain and subnet placement correctly.
###############################################################################

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id  # AZ-A private subnet
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  iam_instance_profile = aws_iam_instance_profile.app_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    # Simple app server stub — replace with your actual application
    yum install -y python3 amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Start a minimal HTTP server on port 8080 to prove connectivity
    python3 -m http.server 8080 &
  EOF

  tags = {
    Name = "${var.project_name}-app-server"
    Role = "app"
  }
}

resource "aws_iam_role" "app_ssm" {
  name = "${var.project_name}-app-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_ssm" {
  name = "${var.project_name}-app-ssm-profile"
  role = aws_iam_role.app_ssm.name
}

###############################################################################
# Nginx EC2 Instance — free-tier t2.micro in public subnet
###############################################################################

resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nginx.id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  iam_instance_profile = aws_iam_instance_profile.nginx_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    yum install -y nginx amazon-ssm-agent
    systemctl enable nginx
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # Configure Nginx as reverse proxy to the app server
    APP_PRIVATE_IP="${aws_instance.app.private_ip}"

    cat > /etc/nginx/conf.d/app.conf <<NGINXCONF
    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass         http://$APP_PRIVATE_IP:8080;
            proxy_set_header   Host \$host;
            proxy_set_header   X-Real-IP \$remote_addr;
            proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto \$scheme;
        }
    }
    NGINXCONF

    systemctl start nginx
  EOF

  tags = {
    Name                 = "${var.project_name}-nginx-proxy"
    Role                 = "nginx"
    ProductionEquivalent = "Application Load Balancer"
  }

  # Nginx must come up after the app server so the private IP is known
  depends_on = [aws_instance.app]
}

resource "aws_iam_role" "nginx_ssm" {
  name = "${var.project_name}-nginx-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nginx_ssm" {
  role       = aws_iam_role.nginx_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nginx_ssm" {
  name = "${var.project_name}-nginx-ssm-profile"
  role = aws_iam_role.nginx_ssm.name
}
