###############################################
# AWS & Project Configuration
###############################################
aws_region   = "us-east-1"
project_name = "selfheal-app"


###############################################
# EC2 Key Pair & AMI Configuration
###############################################
# Replace with your actual EC2 Key Pair name
key_pair_name = "Web-Server-Key"

# Custom AMI (Amazon Linux 2). Leave as-is unless you want to override.
ami_id = "ami-0c94855ba95c71c99"

# Instance type for Bastion + ASG
instance_type = "t3.micro"


###############################################
# VPC & Subnet CIDRs
###############################################
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]


###############################################
# Auto Scaling Group Sizing
###############################################
desired_capacity = 2
min_size         = 2
max_size         = 4


###############################################
# Alerts (SNS Email Subscription)
###############################################
alert_email = "niteshpunia15@gmail.com"
