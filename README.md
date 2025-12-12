# Self-Healing Web Application on AWS

## Overview
This project demonstrates a self-healing web application on AWS. It provisions a complete infrastructure including:

- VPC with public and private subnets
- Bastion host for secure access to private instances
- EC2 instances in private subnets managed by an Auto Scaling Group
- Application Load Balancer (ALB) with health checks
- CloudWatch monitoring, alarms, and dashboards
- Lambda function for self-healing EC2 instances
- SNS topics for alert notifications

Resources can be created **manually via AWS Console** or **automatically using Terraform**.

---

## Prerequisites
Before deploying this project, ensure you have:

- AWS account with appropriate permissions
- AWS CLI configured with your credentials
- Terraform v1.5+ installed
- Python 3.9+ (for Lambda testing or script modifications)
- ZIP utility to package Lambda functions
- Basic understanding of AWS networking concepts

---

## Manual Setup

1. **Networking**
   - Create a VPC with CIDR `10.0.0.0/16`
   - Create public and private subnets:
     - Public: `10.0.1.0/24`, `10.0.2.0/24`
     - Private: `10.0.101.0/24`, `10.0.102.0/24`
   - Attach an Internet Gateway
   - Set up route tables:
     - Public subnets → IGW
     - Private subnets → NAT Gateway (deployed in first public subnet)

2. **Security Groups**
   - Bastion SG: allow SSH from your IP
   - Web SG: allow HTTP from ALB and SSH from Bastion
   - ALB SG: allow HTTP from anywhere

3. **Instances**
   - Launch bastion host in public subnet
   - Launch web instances in private subnets
   - Attach appropriate SGs

4. **ALB**
   - Create Application Load Balancer in public subnets
   - Configure Target Group for private instances (port 80)
   - Set up HTTP listener and health checks

5. **Auto Scaling Group**
   - Create a launch template using user_data.sh for instance initialization
   - Configure ASG across private subnets
   - Attach ASG to ALB target group

6. **Lambda Function**
   - Deploy Lambda (`self_heal.zip`) with Python 3.10 runtime
   - Attach IAM role with permissions to reboot EC2 instances
   - Trigger Lambda via CloudWatch event on EC2 status impairments

7. **SNS and CloudWatch**
   - Create SNS topics for alerts
   - Configure CloudWatch alarms for high CPU (>95%)
   - Set up CloudWatch dashboard to monitor EC2 CPU and ALB healthy hosts

---

## Terraform Setup

1. **Clone the Repository**
```sh
git clone <repository-url>
cd <repository-folder>
```

2. **Configure Variables**
   - Edit terraform.tfvars:
```sh
aws_region     = "ap-south-1"
project_name   = "selfheal-app"
environment    = "prod"

vpc_cidr       = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

key_pair_name  = "your-keypair"
ami_id         = "ami-xxxxxxxxxxxx"  # Optional: overrides default Amazon Linux 2
instance_type  = "t2.micro"

desired_capacity = 2
min_size         = 1
max_size         = 3

alert_email      = "your-email@example.com"
```

3. **Deploy Terraform**
```sh
terraform init
terraform validate
terraform plan
terraform apply
```
   - Confirm with yes to provision resources
   - Outputs include bastion host public IP, ALB DNS, and Lambda function ARN

---

## Configuration Notes for Users

1. **Variables**
   - Update terraform.tfvars to match your AWS environment (region, key pair, AMIs, CIDR blocks)
   - alert_email must be a valid email to receive SNS notifications

2. **User Data**
   - Modify user_data.sh if you need custom EC2 initialization scripts

3. **Lambda**
   - Update lambda/handler.py and re-zip to self_heal.zip if custom logic is required

4. **Bastion Access**
   - To connect to private EC2 instances via bastion:
```sh
ssh -i <your-key.pem> -o ProxyCommand="ssh -i <your-key.pem> ec2-user@<bastion-public-ip> -W %h:%p" ec2-user@<private-ec2-ip>
```

---

## File Structure

```
Self-Healing-WebApp
├── infra/
│   ├── main.tf              # Terraform resources
│   ├── variables.tf         # Terraform variables
│   ├── outputs.tf           # Terraform outputs
│   ├── terraform.tfvars     # Terraform configuration values
│   ├── user_data.sh         # EC2 initialization script
│   │
│   └──lambda/
│       ├── handler.py       # Lambda function code
│       └── self_heal.zip    # Lambda deployment package
│
├── manually created resources/
│   ├──lambda/
│   │  └──handler.py
│   │
│   └──Self-Healing-WebApp-Report.docx
│
├── screenshorts/
│
└── README.md
```

---

## Conclusion

This project provides a production-ready, fault-tolerant, self-healing web application infrastructure on AWS.

It is ideal for:
- Learning AWS infrastructure automation 
- Practicing Terraform deployments
- Building resilient web applications with automated recovery