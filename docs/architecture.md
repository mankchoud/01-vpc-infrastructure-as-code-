# Architecture — Project 2: VPC Infrastructure as Code

## Free-Tier Architecture

```
                          INTERNET
                              │
                              ▼
                    ┌─────────────────┐
                    │ Internet Gateway │  (free)
                    └────────┬────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │           PUBLIC SUBNETS             │
          │                                      │
          │  ┌──────────────┐  ┌──────────────┐  │
          │  │ Nginx EC2    │  │ NAT Instance │  │
          │  │ t2.micro     │  │ t2.micro     │  │
          │  │ (port 80/443)│  │ (MASQUERADE) │  │
          │  │ [ALB in prod]│  │ [NAT GW prod]│  │
          │  └──────┬───────┘  └──────────────┘  │
          └─────────┼────────────────────────────┘
                    │ port 8080
          ┌─────────┼────────────────────────────┐
          │         │     PRIVATE SUBNETS          │
          │         ▼                              │
          │  ┌──────────────┐                     │
          │  │ App EC2      │──── outbound ──────▶ NAT
          │  │ t2.micro     │    (updates)
          │  │ port 8080    │
          │  └──────┬───────┘
          └─────────┼────────────────────────────┘
                    │ port 5432
          ┌─────────┼────────────────────────────┐
          │         ▼       DATA SUBNETS           │
          │  ┌──────────────┐                     │
          │  │ [DB here in  │  NO internet route  │
          │  │  production] │  S3/DynamoDB via    │
          │  │              │  VPC Endpoints only │
          │  └──────────────┘                     │
          └────────────────────────────────────────┘

VPC Flow Logs ──▶ CloudWatch Logs (7-day retention)
              └──▶ S3 Bucket (30-day retention)

VPC Endpoints: S3 Gateway, DynamoDB Gateway (both free)
```

## File Map

| File | Purpose |
|---|---|
| `main.tf` | Provider, backend, data sources |
| `variables.tf` | All input variables with descriptions |
| `terraform.tfvars` | Variable values for this environment |
| `vpc.tf` | VPC, all subnets, Internet Gateway |
| `routing.tf` | Route tables and subnet associations |
| `nat.tf` | NAT Instance + EIP (replaces NAT Gateway) |
| `security_groups.tf` | All SGs + EC2 instances (Nginx, App) |
| `nacls.tf` | Network ACLs for each subnet tier |
| `endpoints.tf` | S3 + DynamoDB Gateway Endpoints |
| `flow_logs.tf` | VPC Flow Logs to CloudWatch + S3 |
| `outputs.tf` | Useful values after apply |

## Quick Start

```bash
# 1. Install Terraform >= 1.6.0
# 2. Configure AWS CLI
aws configure

# 3. Initialise
cd terraform/
terraform init

# 4. Preview what will be created
terraform plan

# 5. Deploy
terraform apply

# 6. Test the traffic flow
curl http://<nginx_public_ip>

# 7. Access instances without SSH (via SSM)
aws ssm start-session --target <instance-id>

# 8. Tear down when done (stops free-tier instance hours)
terraform destroy
```

## Instance Budget Management

You get 750 t2.micro hours/month free. This project uses 3 instances.
3 instances × 24hr × 31 days = 2,232 hours — exceeds the free tier.

**Stop instances when not working:**
```bash
aws ec2 stop-instances --instance-ids <nat-id> <nginx-id> <app-id>
aws ec2 start-instances --instance-ids <nat-id> <nginx-id> <app-id>
```

Or `terraform destroy` at the end of each session and `terraform apply` to rebuild.
State is local, so rebuilding is fast (~2 minutes).
