# Each service has its own private repository and independent release versions.
resource "aws_ecr_repository" "service" {
  for_each = toset(var.service_names)

  name                 = "${var.repository_prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}
