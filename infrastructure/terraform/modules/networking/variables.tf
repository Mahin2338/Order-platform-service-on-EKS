variable "name" {
  description = "Name prefix for the VPC and its resources."
  type        = string
}

variable "vpc_cidr" {
  description = "Canonical IPv4 /16 network. If changed, also update the explicit subnet ranges in main.tf."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr)) && try(cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0], false)
    error_message = "Use a canonical IPv4 /16 network, such as 10.0.0.0/16."
  }
}

variable "availability_zones" {
  description = "Exactly three distinct AZs in the provider's region, in stable order."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 3 && length(distinct(var.availability_zones)) == 3
    error_message = "Provide exactly three distinct availability zones."
  }
}

variable "tags" {
  description = "Additional tags for network resources."
  type        = map(string)
  default     = {}
}
