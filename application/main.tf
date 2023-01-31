# Reusable variables
locals {
  template_bucket_name = join("-", [var.company, var.environment, "alarm-templates"])
  template_bucket      = aws_s3_bucket.cfn_templates.bucket
  account_id           = data.aws_caller_identity.current.account_id
  assume_role_arn      = module.automations_role.role_arn
}

# Alarm manager SSM automations
module "automations" {
  source = "../modules/aws_ssm_document"
  for_each = fileset(path.module, "documents/*.tpl")

  name            = join("-", [var.company, var.environment, trimsuffix(trimprefix(each.key, "documents/"), ".tpl")])
  document_type   = "Automation"
  document_format = "YAML"
  content         = templatefile(each.key, {
  "company" = var.company,
  "template_bucket"         = local.template_bucket,
  "assume_role_arn"         = local.assume_role_arn,
  "sns_topic_high"          = var.sns_topic_high,
  "sns_topic_low"           = var.sns_topic_low,
  "environment"             = var.environment,
  "aws_region"              = var.aws_region,
  "application"             = var.application,
  "application_runbook_url" = var. application_runbook_url})
  
  share_account_ids = var.share_account_ids

  document_tags = {
    "environment"     = var.environment
    "automation-template" = each.key
  }
}

# Create bucket for cloudformation templates
resource "aws_s3_bucket" "cfn_templates" {
  bucket = local.template_bucket_name
  acl    = "private"

  tags = {
    Name        = local.template_bucket_name
    environment = var.environment
    automation = "terraform"
  }
}

# Upload cloudformation templates to S3 bucket
resource "aws_s3_bucket_object" "cfn_templates" {
  for_each = fileset(path.module, "cloudformation-templates/*.yaml")

  bucket =  local.template_bucket
  key    = trimprefix(each.key, "cloudformation-templates/")
  source = each.key

  etag = filemd5(each.key)
}

# Cloudwatch event rules to trigger automations
module "cloudwatch_event_rules" {
  source   = "../modules/aws_cloudwatch_event_rule"
  for_each = fileset(path.module, "cloudwatch-event-rules/*.json")

  name          = join("-", [var.company, var.environment, trimsuffix(trimprefix(each.key, "cloudwatch-event-rules/"), ".json"), "alarms-event-rule"])
  description   = join(" ", ["A cloudwatch event rule to", trimsuffix(trimprefix(each.key, "cloudwatch-event-rules/"), ".json"), "alarms on", trimsuffix(trimprefix(each.key, "cloudwatch-event-rules/"), ".json"), "events."])
  event_pattern = file(each.key)

  create_event_target  = "true"
  target_resource_arn  = join("", ["arn:aws:ssm:", var.aws_region, ":", local.account_id, ":automation-definition/", join("-", [var.company, var.environment, trimsuffix(trimprefix(each.key, "cloudwatch-event-rules/"), ".json"), "alarms-automation:$DEFAULT"])])
  policy_actions       = ["ssm:StartAutomationExecution"]
  input_paths          = lookup(var.input_paths_map, trimsuffix(trimprefix(each.key, "cloudwatch-event-rules/"), ".json"))
  input_template       = var.input_template_map[trimsuffix(trimprefix(each.key, "cloudwatch-event-rules/"), ".json")]

}

module "automations_role" {
  source   = "../modules/aws_iam_role"
  name        = join("-", [var.company, var.environment, "alarm-automations"])
  enabled     = "true"
  description = "This role will be used by the automations to launch stacks and create resources."

  policy = data.aws_iam_policy_document.automations.json
  trust = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ssm.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "automations" {
  statement {
      actions = [
        "ssm:DescribeInstanceInformation",
        "ec2:DescribeTags",
        "ec2:DescribeInstances",
        "ec2:DescribeHosts",
        "rds:DescribeDBInstances",
        "rds:ListTagsForResource",
        "sqs:*",
        "cloudformation:CreateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks",
        "cloudwatch:ListMetrics",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:PutCompositeAlarm",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeTargetGroups",
        "s3:GetObject",
        "sns:Publish"
      ]
      resources = [
        "*"
      ]
      effect = "Allow"
  }

  statement {
      actions = [
        "ssm:StartAutomationExecution"
      ]
      resources = [
        join(":",["arn:aws:ssm",var.aws_region,data.aws_caller_identity.current.account_id,join("/",["automation-definition",join("-",[var.company,var.environment,"delete-ec2-alarms-automation"])]),"$DEFAULT"]),
        join(":",["arn:aws:ssm",var.aws_region,data.aws_caller_identity.current.account_id,join("/",["automation-definition",join("-",[var.company,var.environment,"create-ec2-alarms-automation"])]),"$DEFAULT"])
      ]
      effect = "Allow"
  }

  statement {
      actions = [
        "ssm:GetAutomationExecution"
      ]
      resources = [
        join(":",["arn:aws:ssm",var.aws_region,data.aws_caller_identity.current.account_id,join("/",["automation-execution","*"])])
      ]
      effect = "Allow"
  }
}


     