output "state_bucket" {
  description = "S3 bucket for Terraform remote state."
  value       = aws_s3_bucket.state.bucket
}

output "ecr_repository_url" {
  description = "ECR repository URL."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name used by the release workflow."
  value       = aws_ecr_repository.app.name
}

output "ecr_registry" {
  description = "ECR registry host used by the release workflow."
  value       = split("/", aws_ecr_repository.app.repository_url)[0]
}

output "github_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC."
  value       = aws_iam_role.deploy.arn
}

output "aws_region" {
  description = "Region used by the bootstrap resources."
  value       = var.aws_region
}
