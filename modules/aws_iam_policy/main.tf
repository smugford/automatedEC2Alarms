resource "aws_iam_policy" "main" {
  count = var.enabled
  name  = var.name

  path        = "/"
  description = var.description
  policy      = var.policy
}
