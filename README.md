# bam-automation

This is a POC of an alarm manager driven by CloudWatch Events, SSM Automations and CloudFormation Stacks.

## Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- Install [Runway](https://docs.onica.com/projects/runway/en/release/installation.html)
- For custom metric alarms you will need to run the ssm automation `onboard-cloudwatch-agent` against your instances to install CWAgent and configure it with the provided custom metrics config file

## Deployment
   
Change the DEPLOY_ENVIRONMENT to AWS profile name for the account. i.e lab, dev, prod, test
   
```
DEPLOY_ENVIRONMENT=lab runway deploy
```

## Destruction

Change the DEPLOY_ENVIRONMENT to AWS profile name for the account. i.e lab, dev, prod, test

```
DEPLOY_ENVIRONMENT=lab runway destroy
```
## Built With

* Terraform >= 0.13.0
* Runway > 1.5.0

## todo
- Add cloudwatch event module for each action (document) to eliminate manual changes to event targets (document)
- Ability to handle multiple target groups for ALBs and NLBs

## Future state
- Add a check on `create*DiskAlarms` to add alerts only for metrics that have active data points (within the last 3 hours) [RecentlyActive='PT3H'](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/cloudwatch.html#CloudWatch.Client.get_metric_data)
- Ability to have the alarms auto tune based on known metric history (api call in automation to get average high cpu)
- EBS event will trigger the automation to run and add metrics for the new volume
- Download the alarm states (any information we want to save) and store it in an s3 bucket for audit purposes when alarms are deleted

## Authors
* **Scott Mugford**
* **Mind Guja**
* **Matt Van Zanten**
* **Denis Simonovski**

## Diagram

![Diagram](diagram.png)