###############################################
# General Project Settings
# Basic inputs used across the entire infra.
###############################################
variable "aws_region" {
  description = "AWS region where all resources will be deployed."
  type        = string
}

variable "project_name" {
  description = "Base name used for tagging and naming AWS resources."
  type        = string
}

variable "environment" {
  description = "Environment name (prod/dev/test)."
  type        = string
}


###############################################
# VPC & Networking Configurations
###############################################
variable "vpc_cidr" {
  description = "CIDR block for the main VPC."
  type        = string
}

variable "public_subnets" {
  description = "List of CIDRs for public subnets."
  type        = list(string)
}

variable "private_subnets" {
  description = "List of CIDRs for private subnets."
  type        = list(string)
}


###############################################
# EC2 / Compute Settings
###############################################
variable "instance_type" {
  description = "Instance type to use for EC2 instances."
  type        = string
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access."
  type        = string
}

variable "ami_id" {
  description = "Optional: Custom AMI ID to override default Amazon Linux 2 lookup."
  type        = string
  default     = null
}


###############################################
# Auto Scaling Group (ASG) Configuration
###############################################
variable "desired_capacity" {
  description = "Desired number of EC2 instances in the ASG."
  type        = number
}

variable "min_size" {
  description = "Minimum number of instances for the ASG."
  type        = number
}

variable "max_size" {
  description = "Maximum number of instances for the ASG."
  type        = number
}


###############################################
# Notifications & Monitoring
###############################################
variable "alert_email" {
  description = "Email address that receives critical alerts via SNS."
  type        = string
}
