###############################################################################
# outputs.tf — Output Values
# Useful values printed after terraform apply.
###############################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "IDs of the data subnets"
  value       = aws_subnet.data[*].id
}

output "nat_instance_id" {
  description = "EC2 instance ID of the NAT Instance"
  value       = aws_instance.nat.id
}

output "nat_instance_public_ip" {
  description = "Public IP of the NAT Instance (Elastic IP)"
  value       = aws_eip.nat_instance.public_ip
}

output "nginx_instance_id" {
  description = "EC2 instance ID of the Nginx proxy (ALB substitute)"
  value       = aws_instance.nginx.id
}

output "nginx_public_ip" {
  description = "Public IP of the Nginx proxy — this is your entry point"
  value       = aws_instance.nginx.public_ip
}

output "app_instance_id" {
  description = "EC2 instance ID of the App server"
  value       = aws_instance.app.id
}

output "app_private_ip" {
  description = "Private IP of the App server (not reachable from internet)"
  value       = aws_instance.app.private_ip
}

output "flow_log_cloudwatch_group" {
  description = "CloudWatch Log Group for VPC Flow Logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "flow_log_s3_bucket" {
  description = "S3 bucket storing VPC Flow Logs"
  value       = aws_s3_bucket.flow_logs.bucket
}

output "s3_endpoint_id" {
  description = "S3 Gateway Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "dynamodb_endpoint_id" {
  description = "DynamoDB Gateway Endpoint ID"
  value       = aws_vpc_endpoint.dynamodb.id
}

output "how_to_access_instances" {
  description = "Instructions for accessing instances (no SSH port required)"
  value       = <<-EOT
    Access instances via AWS Systems Manager Session Manager:
      aws ssm start-session --target ${aws_instance.nginx.id}   (Nginx)
      aws ssm start-session --target ${aws_instance.app.id}     (App server)
      aws ssm start-session --target ${aws_instance.nat.id}     (NAT instance)

    Or use the AWS Console → EC2 → Connect → Session Manager.

    Test the full traffic flow:
      curl http://${aws_instance.nginx.public_ip}
  EOT
}
