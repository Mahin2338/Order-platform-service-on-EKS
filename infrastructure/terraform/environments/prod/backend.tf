terraform {
  backend "s3" {
    bucket       = "order-platform-tfstate-792289066018-eu-west-2"
    region       = "eu-west-2"
    key          = "order-platform/prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
