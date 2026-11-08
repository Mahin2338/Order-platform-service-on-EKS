output "vpc_id" {
  description = "Production VPC ID."
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets for the future EKS managed node groups."
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnets for future internet-facing load balancers."
  value       = module.networking.public_subnet_ids
}

output "ecr_repository_urls" {
  description = "Private image repository URL for each application service."
  value       = module.ecr.repository_urls
}

output "github_ecr_publish_role_arn" {
  description = "GitHub ecr-publish environment AWS_ROLE_ARN value."
  value       = module.iam.github_ecr_publish_role_arn
}

output "rds_address" {
  description = "Private PostgreSQL hostname."
  value       = module.rds.address
}

output "rds_master_user_secret_arn" {
  description = "RDS administrator secret reference."
  value       = module.rds.master_user_secret_arn
}
