variable "publish_role_name" {
  description = "IAM role name for GitHub's ECR publishing job."
  type        = string
}

variable "github_publish_subject" {
  description = "Exact GitHub OIDC subject for the repository publishing environment."
  type        = string
}

variable "ecr_repository_arns" {
  description = "Only these repositories can be inspected and uploaded to by CI."
  type        = list(string)
}
