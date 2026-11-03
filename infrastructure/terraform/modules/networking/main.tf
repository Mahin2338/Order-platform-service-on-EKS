# Reuse the community VPC module from the Terraform Registry.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  # One subnet per AZ, in the same order as availability_zones.
  # These ranges belong to 10.0.0.0/16; update them if the VPC CIDR changes.
  private_subnets = [
    "10.0.0.0/24",
    "10.0.16.0/24",
    "10.0.32.0/24",
  ]

  public_subnets = [
    "10.0.240.0/24",
    "10.0.241.0/24",
    "10.0.242.0/24",
  ]

  enable_dns_support   = true
  enable_dns_hostnames = true
  create_igw           = true

  # A public route does not require auto-assigning public IPs to instances.
  map_public_ip_on_launch = false

  # Each private subnet routes outbound traffic through NAT in its own AZ.
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # Help the load-balancer controller find public subnets for the app entry point.
  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }

  # Workloads will use their own security groups, not the default group.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  tags = var.tags
}
