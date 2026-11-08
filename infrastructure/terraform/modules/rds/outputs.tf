output "address" {
  description = "Database hostname for application configuration."
  value       = module.db.db_instance_address
}

output "master_user_secret_arn" {
  description = "Administrator secret ARN; not the password itself."
  value       = module.db.db_instance_master_user_secret_arn
}
