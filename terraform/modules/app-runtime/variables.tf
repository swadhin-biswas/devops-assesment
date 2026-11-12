variable "project" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "devops-task"
}

variable "environment" {
  description = "Environment name, e.g. staging or production."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production."
  }
}

variable "ami_id" {
  description = "Optional pinned AMI ID; empty resolves the latest Ubuntu 24.04 image."
  type        = string
  default     = ""
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

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
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

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs supported retention value."
  }
}

variable "deploy_script_ref" {
  description = "Git ref of scripts/deploy.sh; pin it to a tag or commit for an immutable input."
  type        = string
  default     = "main"
}

variable "deploy_script_sha256" {
  description = "SHA-256 of scripts/deploy.sh at deploy_script_ref; update it with the script."
  type        = string
  default     = "9abc748751932b8e3db28b9f399e7df791011a6c1a6e37b215851c9ff7644153"

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.deploy_script_sha256))
    error_message = "deploy_script_sha256 must be a lowercase 64-character hex SHA-256."
  }
}
