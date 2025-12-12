# Public IP of the Bastion Host
output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

# DNS name of the Application Load Balancer
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

# IDs of EC2 instances in the Auto Scaling Group
data "aws_autoscaling_group" "web_asg_data" {
  name = aws_autoscaling_group.web_asg.name
}

# ARN of the Lambda function for self-healing
output "lambda_function_arn" {
  description = "ARN of the Self-Healing Lambda"
  value       = aws_lambda_function.self_heal_lambda.arn
}

# CloudWatch Dashboard name
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch Dashboard"
  value       = aws_cloudwatch_dashboard.dashboard.dashboard_name
}
