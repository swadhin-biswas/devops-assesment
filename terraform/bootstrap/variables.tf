variable "aws_region" {
  description = "AWS region for the bootstrap resources."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, in owner/name form."
  type        = string
  default     = "swadhinbiswas/devops-assesment"
}

variable "github_branch" {
  description = "GitHub branch allowed to assume the deploy role."
  type        = string
  default     = "main"
}

variable "ecr_repository_name" {
  description = "ECR repository name for application images."
  type        = string
  default     = "devops-task/app"
}

variable "state_bucket_prefix" {
  description = "Prefix for the Terraform state bucket. AWS appends a unique suffix."
  type        = string
  default     = "devops-task-tfstate-"
}

variable "state_bucket_force_destroy" {
  description = "Allow Terraform to delete the state bucket even when it contains objects."
  type        = bool
  default     = false
}

variable "ecr_force_delete" {
  description = "Allow Terraform to delete the ECR repository even when it contains images."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default = {
    Project   = "devops-task"
    ManagedBy = "terraform"
  }
}
