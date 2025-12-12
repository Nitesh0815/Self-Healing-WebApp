###############################################
# Provider Setup
# Just telling Terraform which cloud + region
###############################################
provider "aws" {
  region = var.aws_region
}

###########################################################
# AMI Lookup
# Pulls the latest Amazon Linux 2 AMI for the current region.
# This keeps things dynamic and avoids hardcoding AMI IDs.
###########################################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###########################################################
# VPC + Networking Section
# Main VPC, Internet Gateway, and Subnets (public + private)
###########################################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet access entry point
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Just grabbing available AZs so subnets can spread nicely
data "aws_availability_zones" "available" {}

###########################################################
# Public Subnets
# These host the ALB, Bastion Host, and NAT Gateway.
###########################################################
resource "aws_subnet" "public" {
  for_each                = toset(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true

  # Spread subnets across AZs based on index
  availability_zone = element(
    data.aws_availability_zones.available.names,
    index(var.public_subnets, each.value)
  )

  tags = {
    Name = "${var.project_name}-public-${each.value}"
  }
}

###########################################################
# Private Subnets
# These are where your application servers live (ASG instances).
###########################################################
resource "aws_subnet" "private" {
  for_each          = toset(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = element(
    data.aws_availability_zones.available.names,
    index(var.private_subnets, each.value)
  )

  tags = {
    Name = "${var.project_name}-private-${each.value}"
  }
}

###########################################################
# Routing – Public + Private
###########################################################

# Public Route Table → Internet Gateway
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

###########################################################
# NAT Gateway Setup
# Only ONE NAT is created in the FIRST public subnet.
# Private subnets use this NAT to reach the internet.
###########################################################

resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[var.public_subnets[0]].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_eip.nat_eip]
}

# Private route table sending outbound traffic → NAT
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt.id
}

###########################################################
# Security Groups – Keeping Traffic Safe and Controlled
###########################################################

# ALB SG → Allows internet HTTP traffic
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SSH Security Group for Bastion
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Web Server SG → ALB HTTP + Bastion SSH
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow ALB HTTP + Bastion SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###########################################################
# Bastion Host – Jump Server in Public Subnet
###########################################################
resource "aws_instance" "bastion" {
  ami                         = coalesce(var.ami_id, data.aws_ami.amazon_linux.id)
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.public[var.public_subnets[0]].id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-bastion"
  }
}

###########################################################
# Application Load Balancer + Target Group + Listener
###########################################################
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  subnets            = [for k in var.public_subnets : aws_subnet.public[k].id]
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # ALB health checks – pretty standard config
  health_check {
    path                = "/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

###########################################################
# IAM Role for CloudWatch Agent (EC2)
###########################################################
resource "aws_iam_role" "cw_agent_role" {
  name = "${var.project_name}-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach essential monitoring policies
resource "aws_iam_role_policy_attachment" "cw_agent_policy" {
  role       = aws_iam_role.cw_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cw_logs_policy" {
  role       = aws_iam_role.cw_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.cw_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 Instance Profile for attaching the role
resource "aws_iam_instance_profile" "cw_agent_instance_profile" {
  name = "${var.project_name}-cw-agent-profile"
  role = aws_iam_role.cw_agent_role.name
}

###########################################################
# Launch Template + Auto Scaling Group
###########################################################
resource "aws_launch_template" "web_lt" {
  name          = "${var.project_name}-lt"
  image_id      = coalesce(var.ami_id, data.aws_ami.amazon_linux.id)
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.cw_agent_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  metadata_options {
    http_tokens   = "required" # enforce IMDSv2
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-web"
    }
  }

  # User data contains app + monitoring setup
  user_data = filebase64("${path.module}/user_data.sh")
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  # Use all private subnets
  vpc_zone_identifier = values(aws_subnet.private)[*].id

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  force_delete              = true
}

###########################################################
# IAM Role + Permissions for Lambda (Self-Healing)
###########################################################
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ec2_reboot" {
  name = "${var.project_name}-lambda-ec2-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:RebootInstances"]
      Resource = "*"
    }]
  })
}

###########################################################
# Self-Healing Lambda Function
###########################################################
resource "aws_lambda_function" "self_heal_lambda" {
  function_name = "${var.project_name}-selfheal-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.10"
  timeout       = 10

  filename         = "${path.module}/lambda/self_heal.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/self_heal.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.selfheal_topic.arn
    }
  }

  tags = {
    Name = "${var.project_name}-lambda"
  }
}

# CloudWatch Event Rule → triggers Lambda when EC2 becomes "impaired"
resource "aws_cloudwatch_event_rule" "selfheal_rule" {
  name        = "${var.project_name}-selfheal-rule"
  description = "Triggers lambda on EC2 status impaired"

  event_pattern = <<EOF
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance Status-change Notification"],
  "detail": {
    "state": ["impaired"]
  }
}
EOF
}

# Connect rule → Lambda
resource "aws_cloudwatch_event_target" "selfheal_target" {
  rule      = aws_cloudwatch_event_rule.selfheal_rule.name
  target_id = "lambda-target"
  arn       = aws_lambda_function.self_heal_lambda.arn
}

# Permission allowing CW Events to call Lambda
resource "aws_lambda_permission" "allow_cw" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_heal_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.selfheal_rule.arn
}

###########################################################
# SNS Topics – Alerts & Notifications
###########################################################
resource "aws_sns_topic" "selfheal_topic" {
  name = "${var.project_name}-selfheal-topic"
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Subscribe Lambda to alerts SNS so alarms can trigger Lambda via SNS
resource "aws_sns_topic_subscription" "lambda_from_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.self_heal_lambda.arn
}

# Permission granting SNS the ability to invoke the Lambda
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_heal_lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

###########################################################
# CloudWatch Alarm – High CPU → SNS (and Lambda via SNS)
###########################################################
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 95
  alarm_description   = "Triggers SNS when EC2 CPU > 95%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  # CloudWatch Alarm → publish to SNS. Lambda will receive SNS messages via subscription.
  alarm_actions = [
    aws_sns_topic.alerts.arn
  ]
}

###########################################################
# CloudWatch Dashboard – Simple visual view
###########################################################
resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web_asg.name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EC2 CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          metrics = [
            # ALB Healthy Host count
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.alb.arn_suffix]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ALB Healthy Hosts"
        }
      }
    ]
  })
}
