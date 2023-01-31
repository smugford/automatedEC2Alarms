terraform {
  required_version = ">= 0.13.3" # Minimal version of Terraform
  backend "s3" {
    encrypt = true
  }
}
