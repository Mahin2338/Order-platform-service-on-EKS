variable "identifier" {
  description = "Name identifying the RDS instance in AWS."
  type        = string
}

variable "instance_class" {
  description = "RDS instance size selected by the environment."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets across at least two availability zones."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC containing the database and EKS workers."
  type        = string
}

variable "worker_security_group_id" {
  description = "Security group attached to the EKS workers allowed to connect."
  type        = string
}

variable "db_name" {
  description = "Initial application database name."
  type        = string
}

variable "username" {
  description = "Initial database administrator username."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
}

variable "family" {
  description = "Parameter group family matching the engine major version."
  type        = string
}

variable "allocated_storage" {
  description = "Initial database storage in GiB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
}

variable "multi_az" {
  description = "Whether to maintain a standby in another availability zone."
  type        = bool
}

variable "backup_retention_period" {
  description = "Days to retain automated backups; zero disables them."
  type        = number
}

variable "deletion_protection" {
  description = "Whether to block database deletion."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when deleting the database."
  type        = bool
}

variable "delete_automated_backups" {
  description = "Whether to delete automated backups with the database."
  type        = bool
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC."
  type        = string
}

variable "auto_minor_version_upgrade" {
  description = "Whether to allow automatic minor engine upgrades."
  type        = bool
}

variable "allow_major_version_upgrade" {
  description = "Whether a requested major engine upgrade is permitted."
  type        = bool
}

variable "tags" {
  description = "Labels applied to the database resources."
  type        = map(string)
}
