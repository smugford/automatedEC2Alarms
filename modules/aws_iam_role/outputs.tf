output "role_arn" {
  value = join("", aws_iam_role.main.*.arn)
}

output "role_name" {
  value = aws_iam_role.main[0].name
}

output "policy_arn" {
  value = module.iam_policy.policy_arn
}
