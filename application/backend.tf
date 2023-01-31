terraform {
  required_version = ">= 0.13.0" # Minimal version of Terraform
  backend "s3" {
    encrypt = true
  }
}
