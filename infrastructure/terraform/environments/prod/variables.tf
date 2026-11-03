variable "prod_account_id" {
  description = "The AWS account ID approved for production deployments."
  type        = string
}

variable "aws_region" {
  description = "AWS region for production resources; use the same region in backend.hcl."
  type        = string
}

variable "vpc_cidr" {
  description = "Production VPC IPv4 /16 network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Three stable AZ names in aws_region. Override when changing region."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
}


variable "eks_operator_role_arn" {
  description = "Existing SSO IAM role granted Kubernetes cluster administrator access."
  type        = string
}
