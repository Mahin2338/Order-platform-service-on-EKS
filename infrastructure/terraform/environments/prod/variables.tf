variable "prod_account_id" {
  description = "The AWS account ID approved for production deployments."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.prod_account_id))
    error_message = "prod_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS region for production resources; use the same region in backend.hcl."
  type        = string
}
