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

module "ecr" {
  source = "../../modules/ecr"

  repository_prefix = "order-platform"
  service_names = [
    "api-gateway",
    "dashboard-api",
    "inventory-service",
    "notification-service",
    "order-service",
    "payment-service",
    "scheduler",
    "shipping-service",
    "worker",
  ]
}

module "iam" {
  source = "../../modules/iam"

  publish_role_name      = "order-platform-github-ecr-publish"
  github_publish_subject = "repo:Mahin2338@198268223/Order-platform-service-on-EKS@1428251630:environment:ecr-publish"
  ecr_repository_arns    = module.ecr.repository_arns
}

module "sqs" {
  source = "../../modules/sqs"

  queue_name                 = "order-events"
  visibility_timeout_seconds = 600
  max_receive_count          = 5
  event_retention_seconds    = 345600  # 4 days
  dlq_retention_seconds      = 1209600 # 14 days
}
