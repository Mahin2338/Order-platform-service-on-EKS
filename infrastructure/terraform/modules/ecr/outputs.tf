output "repository_urls" {
  description = "Private ECR repository URL for each service."
  value       = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}

output "repository_arns" {
  description = "Repository ARNs used to scope the CI publishing role."
  value       = [for repository in aws_ecr_repository.service : repository.arn]
}
