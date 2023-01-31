aws_region  = "us-east-1"
company     = "cloud-brothers"
environment = "test"

share_account_ids = ""
template_bucket   = "bam-alarms-bucket"
sns_topic_high     = "arn:aws:sns:us-east-1:xxxxxxxxxxxx:high_priority"
sns_topic_low      = "arn:aws:sns:us-east-1:xxxxxxxxxxxx:low"

input_paths_map    = { "create-ec2" = { "instance" = "$.detail.instance-id" }, "delete-ec2" = { "instance" = "$.detail.instance-id" }, "create-rds" = { "instance" = "$.detail.SourceIdentifier" }, "delete-rds" = { "instance" = "$.detail.SourceIdentifier" }, "create-elb" = { "ELBv2" = "$.detail.requestParameters.name", "ELB" = "$.detail.requestParameters.loadBalancerName" }, "delete-elb" = { "ELB" : "$.detail.requestParameters.loadBalancerName", "ELBarn" : "$.detail.requestParameters.loadBalancerArn" } }
input_template_map = { "create-ec2" = "{\"InstanceId\":[<instance>]}", "delete-ec2" = "{\"InstanceId\":[<instance>]}", "create-rds" = "{\"DBInstanceIdentifier\":[<instance>]}", "delete-rds" = "{\"DBInstanceIdentifier\":[<instance>]}", "create-elb" = "{\"ELBName\":[<ELBv2>],\"ELBClassicName\":[<ELB>]}", "delete-elb" = "{\"ELBName\":[<ELB>],\"ELBArn\":[<ELBarn>]}" }
