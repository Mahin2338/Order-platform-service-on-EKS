output "github_ecr_publish_role_arn" {
  description = "Set this as AWS_ROLE_ARN in GitHub's ecr-publish environment."
  value       = aws_iam_role.github_ecr_publish.arn
}
