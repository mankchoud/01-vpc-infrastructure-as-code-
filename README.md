# Project 1: VPC Infrastructure as Code

A production-grade, multi-tier VPC on AWS built entirely with Terraform. Security is designed into the architecture — not bolted on afterwards. The network is segmented into three tiers with genuine isolation between them, all deployed without touching the AWS console.

> **AWS Free Tier build.** Every production resource that costs money has a documented substitute. See the [substitutions table](#free-tier-substitutions) below.

---

## Architecture

```
Internet
    │
    ▼
Internet Gateway (free)
    │
    ▼
PUBLIC SUBNETS (10.0.1.0/24 · 10.0.2.0/24)
    ├── Nginx Proxy — t2.micro          [replaces ALB ~$18/mo]
    └── NAT Instance — t2.micro         [replaces NAT Gateway ~$64/mo]
              │
              ▼ port 8080
PRIVATE SUBNETS (10.0.10.0/24 · 10.0.20.0/24)
    └── App Server — t2.micro
              │
              ▼ port 5432
DATA SUBNETS (10.0.100.0/24 · 10.0.200.0/24)
    └── [Database tier — no internet route]

VPC Flow Logs ──▶ CloudWatch Logs (7-day)
              └──▶ S3 (30-day, AES-256 encrypted)

VPC Endpoints ──▶ S3 Gateway (free)
              └──▶ DynamoDB Gateway (free)
```

| Tier | Subnets | Internet Access | What Lives Here |
|---|---|---|---|
| Public | 10.0.1.0/24, 10.0.2.0/24 | Full via IGW | Nginx proxy, NAT Instance |
| Private | 10.0.10.0/24, 10.0.20.0/24 | Outbound only via NAT | Application server |
| Data | 10.0.100.0/24, 10.0.200.0/24 | **None** | Databases |

Both AZs are provisioned in Terraform. AZ-B subnets exist for HA scaling — only AZ-A has running instances in this build.

---

## Security Controls

### Security Groups — Instance Level, Stateful

Traffic flows through a chained SG reference model. Each tier only accepts traffic from the immediately upstream tier — not from CIDRs, not from the internet directly.

```
nginx-sg    →  accepts 80/443 from 0.0.0.0/0
  app-sg    →  accepts 8080 from nginx-sg only
    db-sg   →  accepts 5432 from app-sg only
```

References are to security group IDs, not IP addresses. If the Nginx instance is replaced, the app-sg rule still works without any manual update.

### Network ACLs — Subnet Level, Stateless

NACLs are the second layer of defence. They operate at the subnet boundary and can explicitly deny — something security groups cannot do.

| NACL | Inbound | Outbound |
|---|---|---|
| Public | Allow 80, 443, ephemeral (1024–65535) | Allow all |
| Private | Allow 8080 from public CIDRs + ephemeral return | Allow all |
| Data | Allow 5432 from private CIDRs + ephemeral return · **Deny all else** | Allow VPC CIDR only · **Deny all else** |

The data NACL has explicit `DENY` rules at rule number 32766 — belt-and-braces on top of the route table (no internet route) and the security group.

### VPC Flow Logs

All traffic metadata is captured and shipped to two destinations:

- **CloudWatch Logs** — 7-day retention, query with Logs Insights for real-time investigation
- **S3** — 30-day lifecycle, AES-256 server-side encryption, public access blocked

Flow logs capture: source IP, destination IP, port, protocol, bytes, action (ACCEPT/REJECT). They do not capture packet contents.

Sample Logs Insights query to detect port scans:
```
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| sort @timestamp desc
| limit 50
```

### VPC Endpoints

| Endpoint | Type | Cost | Purpose |
|---|---|---|---|
| S3 Gateway | Gateway | Free | Private/data tier accesses S3 without internet |
| DynamoDB Gateway | Gateway | Free | Private/data tier accesses DynamoDB without internet |

Interface endpoints (SSM, ECR, etc.) are skipped — each costs ~$7/mo. SSM access is handled via the NAT Instance route.

---

## Free-Tier Substitutions

| Production Resource | Substitute Used | Production Cost |
|---|---|---|
| NAT Gateway ×2 (one per AZ) | NAT Instance — t2.micro EC2 | ~$64/mo |
| Application Load Balancer | Nginx reverse proxy — t2.micro EC2 | ~$18/mo |
| Athena (S3 log analysis) | CloudWatch Logs Insights | $5/TB scanned |
| Interface VPC Endpoints | Gateway Endpoints only (S3, DynamoDB) | ~$7/mo each |

Every substitution is commented in the Terraform code with the production equivalent and the reason for the substitution.

**NAT Instance vs NAT Gateway:** The NAT Instance runs Amazon Linux 2 with `net.ipv4.ip_forward = 1` and an iptables `MASQUERADE` rule. Source/destination check is disabled on the EC2 instance — AWS drops forwarded packets by default unless this is explicitly turned off. In production, one NAT Gateway per AZ is the correct approach for resilience and managed scaling.

**Nginx vs ALB:** The Nginx instance sits in the public subnet and reverse-proxies to the app server on port 8080. The security group chain (nginx-sg → app-sg → db-sg) is identical in concept to the ALB-SG → App-SG → DB-SG chain in production. The substitution demonstrates the same security principle.

---

## Terraform File Map

| File | Purpose |
|---|---|
| `main.tf` | Provider, local backend, AMI + AZ data sources |
| `vpc.tf` | VPC, all 6 subnets, Internet Gateway |
| `routing.tf` | 3 route tables — public→IGW, private→NAT, data→local only |
| `nat.tf` | NAT Instance + EIP, IP forwarding, iptables masquerade, SSM IAM role |
| `security_groups.tf` | SG chain (nginx→app→db) + Nginx and App EC2 instances |
| `nacls.tf` | Stateless subnet-level ACLs with explicit deny on data tier |
| `endpoints.tf` | S3 + DynamoDB Gateway Endpoints with account-scoped policy |
| `flow_logs.tf` | Flow Logs → CloudWatch + S3, encryption, lifecycle rule |
| `variables.tf` | All input variables with descriptions and defaults |
| `outputs.tf` | IPs, instance IDs, and SSM access commands |
| `terraform.tfvars` | Variable values for this environment |

---

## Project structure 

├── 01-vpc-infrastructure-as-code/
│   ├── README.md
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── vpc.tf
│   │   ├── routing.tf
│   │   ├── nat.tf
│   │   ├── security_groups.tf
│   │   ├── nacls.tf
│   │   ├── endpoints.tf
│   │   ├── flow_logs.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   └── docs/
│       ├── architecture.md
│       └── security-decisions.md




---

## Quick Start

```bash
cd terraform/

# 1. Initialise — downloads AWS provider (~40MB)
terraform init

# 2. Preview — see exactly what will be created before touching your account
terraform plan

# 3. Deploy
terraform apply

# 4. Test the full traffic chain
curl http://<nginx_public_ip>

# 5. Shell into instances via SSM (no SSH port, no key pair required)
aws ssm start-session --target <instance-id>

# 6. Tear down when done — stops free-tier instance hours
terraform destroy
```

---

## Key Design Decisions

**Why are app servers in private subnets?**
They have no public IP and no inbound internet route. An attacker who scans the internet cannot find them. Even if the Nginx proxy is compromised, reaching the app server still requires breaking through the app-sg (which accepts only from nginx-sg on port 8080). Compromise requires chaining through every layer.

**Why SG references instead of CIDR blocks?**
Security group references are dynamic — they follow the resource, not its IP address. If the Nginx instance is replaced or scaled, the app-sg rule still works without any manual update. Hard-coded CIDRs break when instances change.

**Why two layers (SGs + NACLs)?**
Defence in depth. If a security group is accidentally misconfigured, the NACL provides a subnet-wide backstop that cannot be overridden by instance-level config. The data subnet NACL denies all traffic except PostgreSQL from private subnet CIDRs — three independent controls protect the database tier.

**Why is the NAT Instance source/destination check disabled?**
AWS drops packets where the EC2 instance is neither the source nor the destination. A NAT instance forwards packets on behalf of other instances — so this check must be disabled or all forwarded traffic is silently dropped. This is the most common reason NAT instances appear to start correctly but pass no traffic.

---

## Instance Budget Management

AWS Free Tier provides **750 t2.micro hours/month**. This project uses three instances. Running all three 24/7 uses ~2,232 hours/month — exceeding the free tier.

Stop instances when not actively working:

```bash
# Stop all three
aws ec2 stop-instances --instance-ids <nat-id> <nginx-id> <app-id>

# Or destroy and rebuild — local state is preserved, rebuilds in ~3 minutes
terraform destroy
terraform apply
```

Also note: Elastic IPs charge $0.005/hr when unattached to a running instance. If you stop instances without destroying, the EIP incurs a small charge. `terraform destroy` avoids this entirely.
