###############################################
# Bastion Host Output
###############################################
output "bastion_public_ip" {
  description = "Public IP address of the Bastion Host."
  value       = aws_instance.bastion.public_ip
}


###############################################
# Application Load Balancer Output
###############################################
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.alb.dns_name
}


###############################################
# Auto Scaling Group - Instance Lookup
# (Useful when debugging or validating ASG instances)
###############################################
data "aws_autoscaling_group" "web_asg_data" {
  name = aws_autoscaling_group.web_asg.name
}


###############################################
# Lambda (Self-Healing) Output
###############################################
output "lambda_function_arn" {
  description = "ARN of the Self-Healing Lambda function."
  value       = aws_lambda_function.self_heal_lambda.arn
}


###############################################
# CloudWatch Dashboard
###############################################
output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name for monitoring."
  value       = aws_cloudwatch_dashboard.dashboard.dashboard_name
}
