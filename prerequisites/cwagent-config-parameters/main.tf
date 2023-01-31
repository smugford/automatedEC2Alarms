module "amazon_cloudwatch_windows_config" {
  source = "../../modules/aws_ssm_parameter"

  name            = "AmazonCloudWatch-windows-config"
  type            = "String"
  value           = jsonencode(yamldecode(file("${path.module}/parameters/cw_agent_windows.yaml")))
  allow_overwrite = "true"

  # Additional Tags
  param_tags = { 
    cloud       = "AWS"
    environment = var.environment
  }
}

module "amazon_cloudwatch_linux_config" {
  source = "../../modules/aws_ssm_parameter"

  name            = "AmazonCloudWatch-linux-config"
  type            = "String"
  value           = jsonencode(yamldecode(file("${path.module}/parameters/cw_agent_linux.yaml")))
  allow_overwrite = "true"

  # Additional Tags
  param_tags = { 
    cloud = "AWS"
    environment = var.environment
  }
}

module "onboard_cloudwatch_agent_doc" {
  source = "../../modules/aws_ssm_document"

  for_each = fileset(path.module, "documents/*")
  
  name          = trimsuffix(trimsuffix(trimprefix(each.key, "documents/"), ".json"), ".yaml")
  document_type = "Command"

  content         = file(each.key)
  document_format = upper(substr(each.key, -4, 4))

  share_account_ids = var.share_account_ids
  
  document_tags = {
    environment = var.environment
    file-path = each.key
  }
}