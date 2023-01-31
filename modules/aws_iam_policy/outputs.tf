output "policy_arn" {
  value = join("", aws_iam_policy.main.*.arn)
}
