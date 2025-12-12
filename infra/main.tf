provider "aws" {
  region = var.aws_region
}

# -----------------------------
# Data: Latest Amazon Linux 2 AMI (region-aware)
# -----------------------------
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

# -----------------------------
# VPC, IGW, Subnets
# -----------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

data "aws_availability_zones" "available" {}

# Public subnets (for ALB/Bastion/NAT)
resource "aws_subnet" "public" {
  for_each                = toset(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, index(var.public_subnets, each.value))

  tags = {
    Name = "${var.project_name}-public-${each.value}"
  }
}

# Private subnets (for ASG)
resource "aws_subnet" "private" {
  for_each          = toset(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = element(data.aws_availability_zones.available.names, index(var.private_subnets, each.value))

  tags = {
    Name = "${var.project_name}-private-${each.value}"
  }
}

# -----------------------------
# Route Tables & NAT (one NATGW in first public subnet)
# -----------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-public-rt" }
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

# Elastic IP for NAT
resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-eip" }
}

# NAT Gateway in the first public subnet
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[var.public_subnets[0]].id
  tags          = { Name = "${var.project_name}-nat" }
  depends_on    = [aws_eip.nat_eip]
}

# Private route table using NAT
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
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

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP traffic from internet"
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

resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "SSH access"
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

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow traffic from ALB and Bastion"
  vpc_id      = aws_vpc.main.id

  # allow HTTP from ALB (by referencing ALB SG)
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # allow SSH from bastion security group
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

# -----------------------------
# Bastion Host
# -----------------------------
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

# -----------------------------
# ALB + Target Group + Listener
# -----------------------------
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  subnets = [
    for k in var.public_subnets : aws_subnet.public[k].id
  ]
  security_groups = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

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

# -----------------------------
# IAM Role for CloudWatch Agent (EC2)
# -----------------------------
resource "aws_iam_role" "cw_agent_role" {
  name = "${var.project_name}-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

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

resource "aws_iam_instance_profile" "cw_agent_instance_profile" {
  name = "${var.project_name}-cw-agent-profile"
  role = aws_iam_role.cw_agent_role.name
}

# -----------------------------
# Launch Template + Auto Scaling
# -----------------------------
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
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-web"
    }
  }

  user_data = filebase64("${path.module}/user_data.sh")
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity = var.desired_capacity
  max_size         = var.max_size
  min_size         = var.min_size

  # use values() to convert the for_each map -> list
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

# -----------------------------
# IAM Role for Lambda
# -----------------------------
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
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
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:RebootInstances"]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------
# Lambda Function for Self-Healing
# -----------------------------
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

resource "aws_cloudwatch_event_target" "selfheal_target" {
  rule      = aws_cloudwatch_event_rule.selfheal_rule.name
  target_id = "lambda-target"
  arn       = aws_lambda_function.self_heal_lambda.arn
}


# Allow CloudWatch to invoke the Lambda
resource "aws_lambda_permission" "allow_cw" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_heal_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.selfheal_rule.arn
}


# -----------------------------
# SNS Topic for Notifications
# -----------------------------
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

# -----------------------------
# CloudWatch Alarm for CPU > 95%
# -----------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 95
  alarm_description   = "Triggers Lambda and SNS when EC2 CPU > 95%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [
    aws_lambda_function.self_heal_lambda.arn,
    aws_sns_topic.alerts.arn
  ]
}

# -----------------------------
# CloudWatch Dashboard
# -----------------------------
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
            # Use ApplicationELB namespace and arn_suffix dimension
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
