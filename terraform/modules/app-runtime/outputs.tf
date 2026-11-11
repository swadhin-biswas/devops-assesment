output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP of the instance."
  value       = aws_instance.app.public_ip
}

output "security_group_id" {
  description = "Application security group ID."
  value       = aws_security_group.app.id
}

output "log_group_name" {
  description = "CloudWatch log group for container logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "iam_role_name" {
  description = "Instance IAM role name."
  value       = aws_iam_role.instance.name
}
