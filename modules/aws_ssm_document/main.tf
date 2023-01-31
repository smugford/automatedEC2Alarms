resource "aws_ssm_document" "main" {

  name          = var.name
  document_type = var.document_type

  content         = var.content
  document_format = var.document_format

  permissions = {
    type        = "Share"
    account_ids = var.share_account_ids
  }

  tags = merge(var.tags, var.document_tags)

  lifecycle {
    ignore_changes = [
      permissions
    ]
  }
}