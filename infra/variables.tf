# AWS region
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

# Project name
variable "project_name" {
  description = "Project Name"
  type        = string
  default     = "selfheal-app"
}

# VPC CIDR
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

# Public Subnets
variable "public_subnets" {
  description = "List of Public Subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Private Subnets
variable "private_subnets" {
  description = "List of Private Subnet CIDRs"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# EC2 Key Pair
variable "key_pair_name" {
  description = "Existing EC2 Key Pair Name"
  type        = string
}

# EC2 AMI ID
variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-068c0051b15cdb816" # Amazon Linux 2
}

# EC2 Instance type
variable "instance_type" {
  description = "EC2 Instance type"
  type        = string
  default     = "t3.micro"
}

# Auto Scaling parameters
variable "desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 4
}

variable "alert_email" {
  type        = string
  description = "Email address for SNS alerts"
}