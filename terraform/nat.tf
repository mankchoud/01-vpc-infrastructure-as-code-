###############################################################################
# nat.tf — NAT Instance (Free-Tier Substitute for NAT Gateway)
#
# PRODUCTION SUBSTITUTE:
#   resource "aws_nat_gateway" "az_a" {
#     allocation_id = aws_eip.nat_a.id
#     subnet_id     = aws_subnet.public[0].id
#   }
#   resource "aws_nat_gateway" "az_b" {
#     allocation_id = aws_eip.nat_b.id
#     subnet_id     = aws_subnet.public[1].id
#   }
#   Cost: ~$32/mo each = ~$64/mo total
#
# FREE-TIER APPROACH:
#   A single t2.micro EC2 in the public subnet running Amazon Linux 2 with:
#   - IP forwarding enabled (kernel parameter)
#   - iptables masquerading (SNAT)
#   - Source/Destination Check DISABLED (critical AWS setting)
#
# TRADE-OFF vs Production NAT Gateway:
#   - No built-in HA (single point of failure)
#   - Bandwidth limited to instance type
#   - Requires OS patching
#   - In production: one NAT GW per AZ for resilience
###############################################################################

###############################################################################
# Elastic IP for the NAT Instance
# Cost: FREE while attached to a running instance
###############################################################################

resource "aws_eip" "nat_instance" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-instance-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip_association" "nat_instance" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat_instance.id
}

###############################################################################
# NAT Instance — t2.micro Amazon Linux 2
###############################################################################

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id  # AZ-A public subnet
  vpc_security_group_ids = [aws_security_group.nat.id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  # CRITICAL: Disable source/destination check.
  # By default AWS drops packets where the instance is neither source nor dest.
  # NAT requires forwarding packets on behalf of others — so this MUST be false.
  source_dest_check = false

  # User data: enable IP forwarding + iptables masquerading on boot
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Enable IP forwarding (allows the instance to route packets)
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    # MASQUERADE: rewrite source IP of outbound packets to the instance's IP
    # so that responses from the internet are returned to the NAT instance,
    # which then forwards them back to the private subnet instance.
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    # Persist iptables rules across reboots
    yum install -y iptables-services
    service iptables save
    systemctl enable iptables

    # Install SSM agent (allows console access without SSH key)
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  iam_instance_profile = aws_iam_instance_profile.nat_ssm.name

  tags = {
    Name = "${var.project_name}-nat-instance"
    Role = "nat"
    # Document the production equivalent for reviewers
    ProductionEquivalent = "aws_nat_gateway (one per AZ)"
  }
}

###############################################################################
# IAM Role for SSM access (so you can shell in without SSH port open)
###############################################################################

resource "aws_iam_role" "nat_ssm" {
  name = "${var.project_name}-nat-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat_ssm" {
  name = "${var.project_name}-nat-ssm-profile"
  role = aws_iam_role.nat_ssm.name
}
