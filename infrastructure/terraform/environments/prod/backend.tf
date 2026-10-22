terraform {
  backend "s3" {
    key          = "order-platform/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
