resource "aws_cloudwatch_event_rule" "main" {
  name        = var.name
  description = var.description

  event_pattern = var.event_pattern
}

module "cloudwatch_event_target" {
  source = "../aws_cloudwatch_event_target"
  count  = var.create_event_target ? 1 : 0

  target_resource_arn      = var.target_resource_arn
  cloudwatch_event_rule    = aws_cloudwatch_event_rule.main.name

  input_paths                     = var.input_paths
  input_template                  = var.input_template
  cloudwatch_event_execution_role = module.event_execution_role.role_arn
}

module "event_execution_role" {
  source      = "../aws_iam_role"
  name        = var.name
  enabled     = var.create_event_target
  description = "The role that will be created to execute a defined target from cloudwatch events."

  policy = data.aws_iam_policy_document.main.json
  trust = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "main" {
  statement {
      actions = var.policy_actions
      resources = [var.target_resource_arn]
      effect = "Allow"
  }
}
