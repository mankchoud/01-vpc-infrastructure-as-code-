# Security Decisions — Project 2: VPC Infrastructure as Code

## Free-Tier Substitutions

| Production Resource | Free-Tier Substitute | Reason |
|---|---|---|
| NAT Gateway (×2) | NAT Instance t2.micro (×1) | NAT GW = ~$32/mo each |
| Application Load Balancer | Nginx on t2.micro | All LB types cost ~$16-20/mo |
| Athena (S3 log analysis) | CloudWatch Logs Insights | Athena = $5/TB scanned |
| Interface VPC Endpoints | Gateway Endpoints only (S3, DynamoDB) | Interface endpoints = ~$7/mo each |

---

## Why Are Resources in Private Subnets?

Resources in private subnets cannot be directly reached from the internet.
An attacker can port-scan the entire IPv4 internet — but they will never find
the app servers or databases here because those IPs are RFC-1918 private addresses
with no internet route.

Even if the Nginx proxy is compromised, the attacker still needs to:
1. Break through the App security group (only port 8080 from Nginx SG)
2. Then break through the DB security group (only port 5432 from App SG)

This is defence in depth — multiple independent security layers.

---

## Traffic Allowed In and Out

### Inbound (user request path)
```
Internet → IGW → Nginx EC2 (port 80/443) → App EC2 (port 8080) → [DB port 5432]
```

### Outbound (server update path)
```
App EC2 → NAT Instance → IGW → Internet
```

### Data tier
- No inbound from internet (no route, NACL deny, SG deny — three layers)
- No outbound to internet (no default route in route table)
- Only accepts PostgreSQL (5432) from App SG
- Can reach S3/DynamoDB via Gateway VPC Endpoints

---

## How Security Groups and NACLs Complement Each Other

| Aspect | Security Groups | Network ACLs |
|---|---|---|
| Level | Instance/ENI | Subnet |
| State | Stateful | Stateless |
| Rules | Allow only | Allow + Deny |
| References | Other SGs ✅ | CIDR blocks only |

**SGs handle the fine-grained logic** (e.g., "only accept traffic from the Nginx SG").
**NACLs provide a subnet-wide backstop** — even if an SG is misconfigured,
the NACL can block traffic at the subnet boundary.

The data subnet NACL explicitly denies all inbound except PostgreSQL from private subnets,
and explicitly denies all outbound except to the VPC CIDR.
This is belt-and-braces on top of the route table (no internet route) and SG (port 5432 only).

---

## Where Inspection Lives

This design uses passive inspection via **VPC Flow Logs**:
- All traffic metadata logged to CloudWatch Logs (real-time) and S3 (archive)
- Query rejected traffic in CloudWatch Logs Insights to detect scans

### Sample CloudWatch Logs Insights Queries

**Find all REJECT events (potential port scans or misconfigurations):**
```
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, protocol, action
| filter action = "REJECT"
| sort @timestamp desc
| limit 50
```

**Top talkers (most bytes transferred):**
```
fields srcAddr, dstAddr, bytes
| stats sum(bytes) as totalBytes by srcAddr, dstAddr
| sort totalBytes desc
| limit 20
```

**Traffic to data subnets from unexpected sources:**
```
fields srcAddr, dstAddr, dstPort, action
| filter dstAddr like "10.0.100." or dstAddr like "10.0.200."
| filter srcAddr not like "10.0.10." and srcAddr not like "10.0.20."
| sort @timestamp desc
```

**Production inspection options** (not in free-tier build):
- AWS Network Firewall — stateful layer-7 inspection, domain filtering
- Gateway Load Balancer — inline third-party firewall appliances
- VPC Traffic Mirroring — passive copy of packets to IDS

---

## How This Reduces Attack Surface

1. **Only two IPs reachable from the internet:** Nginx EC2 and NAT Instance
2. **Nginx EC2 accepts only port 80/443** — nothing else, even if an attacker finds the IP
3. **App servers have no public IP** — unreachable from the internet by definition
4. **Data subnets have no internet route** — even a fully compromised app server cannot directly exfiltrate data to the internet from the data tier
5. **SG chain** — each tier only accepts traffic from the immediately upstream tier
6. **NACLs** — subnet-level backstop with explicit deny rules

---

## How This Supports Future Growth

- **Two AZs** — subnets exist in both AZ-A and AZ-B. Scaling to HA requires:
  - Replacing the NAT Instance with one NAT Gateway per AZ
  - Replacing Nginx EC2 with an ALB spanning both public subnets
  - Adding an Auto Scaling Group for the app tier
- **VPC CIDR /16** — 65,536 IPs available. /24 subnets use 256 each, leaving room for many more subnets
- **Terraform modules** — all resources are parameterised via variables; adding a new environment is a new `.tfvars` file
- **VPC Endpoints** — already in place so app servers never need internet access to reach S3/DynamoDB; adding more services means adding Interface endpoints
