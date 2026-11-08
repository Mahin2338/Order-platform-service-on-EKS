# PostgreSQL database using the pinned community RDS module.
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.2"

  identifier                      = var.identifier
  engine                          = "postgres"
  engine_version                  = var.engine_version
  family                          = var.family
  db_name                         = var.db_name
  port                            = 5432
  instance_class                  = var.instance_class
  allocated_storage               = var.allocated_storage
  storage_type                    = "gp3"
  max_allocated_storage           = var.max_allocated_storage
  create_db_subnet_group          = true
  create_db_option_group          = false
  subnet_ids                      = var.subnet_ids
  publicly_accessible             = false
  vpc_security_group_ids          = [aws_security_group.database.id]
  multi_az                        = var.multi_az
  username                        = var.username
  manage_master_user_password     = true
  storage_encrypted               = true
  backup_retention_period         = var.backup_retention_period
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  delete_automated_backups        = var.delete_automated_backups
  copy_tags_to_snapshot           = false
  maintenance_window              = var.maintenance_window
  auto_minor_version_upgrade      = var.auto_minor_version_upgrade
  allow_major_version_upgrade     = var.allow_major_version_upgrade
  tags                            = var.tags
  enabled_cloudwatch_logs_exports = ["postgresql"]
}
