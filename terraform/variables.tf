###############################################################################
# variables.tf — Input Variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (used in tags and resource names)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short project name used as a prefix for all resources"
  type        = string
  default     = "csp2"
}

###############################################################################
# VPC / Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private (app) subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "data_subnet_cidrs" {
  description = "CIDR blocks for data (DB) subnets — NO internet route"
  type        = list(string)
  default     = ["10.0.100.0/24", "10.0.200.0/24"]
}

###############################################################################
# EC2 — Free-tier substitutes
###############################################################################

variable "instance_type" {
  description = "EC2 instance type — t2.micro is free-tier eligible"
  type        = string
  default     = "t2.micro"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Key Pair for SSH access (create in console first)"
  type        = string
  default     = ""  # Leave empty to skip key association (SSM-only access)
}

###############################################################################
# Flow Logs
###############################################################################

variable "flow_log_retention_days" {
  description = "CloudWatch log retention in days (keep low to minimise cost)"
  type        = number
  default     = 7
}
