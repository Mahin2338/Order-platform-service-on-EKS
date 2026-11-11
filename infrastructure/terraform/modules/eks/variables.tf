variable "cluster_name" {
  description = "Name of the EKS cluster and prefix for its service role."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the networking module."
  type        = list(string)
}

variable "operator_role_arn" {
  description = "Existing IAM role used by the human operators; not an STS session ARN."
  type        = string
}

variable "node_ami_type" {
  description = "EKS-optimised AMI type; must match the instance and container architecture."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the worker group."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT worker capacity."
  type        = string
}

variable "node_disk_size" {
  description = "Root disk size in GiB per worker."
  type        = number
}

variable "node_desired_size" {
  description = "Initial desired worker count; this is not workload-driven autoscaling."
  type        = number
}

variable "node_min_size" {
  description = "Minimum worker count."
  type        = number
}

variable "node_max_size" {
  description = "Maximum worker count."
  type        = number
}

variable "node_max_unavailable" {
  description = "Maximum unavailable workers during a managed rolling update."
  type        = number
}

variable "application_namespace" {
  description = "Kubernetes namespace containing the application service accounts."
  type        = string
}

variable "order_service_account_name" {
  description = "Exact Kubernetes service account permitted to assume the order role."
  type        = string
}

variable "order_events_queue_arn" {
  description = "Only this SQS queue may receive messages from the order role."
  type        = string
}

variable "payment_service_account_name" {
  description = "Kubernetes service account trusted by the payment-service IAM role."
  type        = string
}

variable "shipping_service_account_name" {
  description = "Kubernetes service account trusted by the shipping-service IAM role."
  type        = string
}

variable "worker_account_name" {
  description = "Kubernetes service account trusted by the worker IAM role."
  type        = string
}
