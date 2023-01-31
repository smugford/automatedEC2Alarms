resource "aws_iam_role" "main" {
  count = var.enabled ? 1 : 0

  name = join("-", [var.name, "role"])

  assume_role_policy = var.trust
  description        = var.description
}

module "iam_policy" {
  source = "../aws_iam_policy"

  enabled = var.enabled ? 1 : 0
  name    = join("-", [var.name, "policy"])

  policy      = var.policy
  description = var.description
}

resource "aws_iam_role_policy_attachment" "main" {
  count      = var.enabled ? 1 : 0
  role       = aws_iam_role.main[0].name
  policy_arn = module.iam_policy.policy_arn
}
