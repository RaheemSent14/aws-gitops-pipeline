output "repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "aws_access_key_id" {
  description = "Access key for GitHub Actions"
  value       = aws_iam_access_key.ci_user_keys.id
  sensitive   = true
}

output "aws_secret_access_key" {
  description = "Secret key for GitHub Actions"
  value       = aws_iam_access_key.ci_user_keys.secret
  sensitive   = true
}