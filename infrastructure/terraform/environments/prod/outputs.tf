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

output "sqs_queue_url" {
  description = "Application SQS_QUEUE_URL setting."
  value       = module.sqs.queue_url
}

output "sqs_queue_arn" {
  description = "Application queue ARN for workload IAM policies."
  value       = module.sqs.queue_arn
}

output "sqs_dlq_url" {
  description = "DLQ URL for investigating repeatedly failing messages."
  value       = module.sqs.dlq_url
}

output "sqs_dlq_arn" {
  description = "DLQ ARN for monitoring and operator IAM policies."
  value       = module.sqs.dlq_arn
}
