variable "repository_prefix" {
  description = "Namespace used for the private service repositories."
  type        = string
}

variable "service_names" {
  description = "Service names to create matching repositories for."
  type        = list(string)
}
