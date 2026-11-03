output "repository_urls" {
  description = "Private ECR repository URL for each service."
  value       = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}
