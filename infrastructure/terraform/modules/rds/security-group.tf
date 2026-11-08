# Only EKS workers may initiate PostgreSQL connections.
resource "aws_security_group" "database" {
  name        = "${var.identifier}-database"
  description = "PostgreSQL access from EKS workers"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = var.worker_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS workers"
}
