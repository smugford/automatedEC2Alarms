locals {
  template_bucket_name = join("-", [var.company, var.environment, "terraform-state", var.aws_region])
}

resource "aws_s3_bucket" "state" {
  bucket = local.template_bucket_name
  acl    = "private"

  tags = {
    Name        = local.template_bucket_name
    environment = var.environment
    automation = "terraform"
  }
}