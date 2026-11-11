variable "aws_region" {
  description = "AWS region for staging resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8080
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the app port."
  type        = string
  default     = "0.0.0.0/0"
}

variable "image_uri" {
  description = "Full container image URI to run, including tag."
  type        = string
}

variable "app_version" {
  description = "APP_VERSION value passed to the container."
  type        = string
  default     = "0.1.6"
}

variable "log_level" {
  description = "LOG_LEVEL value passed to the container."
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

output "instance_id" {
  description = "Staging EC2 instance ID."
  value       = module.runtime.instance_id
}

output "public_ip" {
  description = "Staging public IP."
  value       = module.runtime.public_ip
}

output "log_group_name" {
  description = "Staging CloudWatch log group."
  value       = module.runtime.log_group_name
}
