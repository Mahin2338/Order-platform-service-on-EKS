output "vpc_id" {
  description = "VPC ID for EKS and other private resources."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs in AZ order; use these for EKS workers."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs in AZ order; use these for internet-facing load balancers."
  value       = module.vpc.public_subnets
}

output "private_route_table_ids" {
  description = "Private route tables, available for later gateway endpoint associations."
  value       = module.vpc.private_route_table_ids
}
