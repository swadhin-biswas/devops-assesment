variable "project" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "devops-task"
}

variable "environment" {
  description = "Environment name, e.g. staging or production."
  type        = string
}

variable "aws_region" {
  description = "AWS region for runtime resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro is Free Tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8080
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the app port. Restrict to your IP for real use."
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
  default     = "2.0.0"
}

variable "app_env" {
  description = "APP_ENV value passed to the container."
  type        = string
  default     = "staging"
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

variable "deploy_script_ref" {
  description = "Git ref of scripts/deploy.sh the instance bootstraps from."
  type        = string
  default     = "main"
}
