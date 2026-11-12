output "state_bucket" {
  description = "S3 bucket for Terraform remote state."
  value       = aws_s3_bucket.state.bucket
}

output "github_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC."
  value       = aws_iam_role.deploy.arn
}

output "aws_region" {
  description = "Region used by the bootstrap resources."
  value       = var.aws_region
}
