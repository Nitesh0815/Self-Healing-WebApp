# AWS region
aws_region     = "us-east-1"

# Project name
project_name   = "selfheal-app"

# EC2 Key Pair (replace with your actual key pair name)
key_pair_name  = "Web-Server-Key"  

# AMI for EC2 instances (Amazon Linux 2)
ami_id         = "ami-0c94855ba95c71c99"

# EC2 instance type
instance_type  = "t3.micro"

# VPC and Subnets
vpc_cidr       = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24","10.0.2.0/24"]
private_subnets = ["10.0.101.0/24","10.0.102.0/24"]

# Auto Scaling Group configuration
desired_capacity = 2
min_size        = 2
max_size        = 4

alert_email = "niteshpunia15@gmail.com"
