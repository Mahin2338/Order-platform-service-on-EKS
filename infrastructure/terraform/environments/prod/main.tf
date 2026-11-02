module "networking" {
  source = "../../modules/networking"

  name               = "order-platform-prod"
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "eks" {
  source = "../../modules/eks"

  operator_role_arn  = var.eks_operator_role_arn
  cluster_name       = "order-platform-prod"
  private_subnet_ids = module.networking.private_subnet_ids

  node_ami_type        = "AL2023_x86_64_STANDARD"
  node_instance_types  = ["t3.small"]
  node_capacity_type   = "ON_DEMAND"
  node_disk_size       = 20
  node_desired_size    = 3
  node_min_size        = 3
  node_max_size        = 4
  node_max_unavailable = 1
}
