resource "aws_cloudwatch_event_target" "main" {
  arn       = var.target_resource_arn
  rule      = var.cloudwatch_event_rule
  role_arn  = var.cloudwatch_event_execution_role

  input_transformer {
    input_paths = var.input_paths
    input_template = var.input_template
  }
}