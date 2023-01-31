resource "aws_ssm_parameter" "main" {
  name      = var.name
  type      = var.type
  value     = var.value
  overwrite = var.allow_overwrite

  tags = merge(var.param_tags, var.tags)
}