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
