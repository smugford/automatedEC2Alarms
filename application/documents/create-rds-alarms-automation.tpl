description: Create Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  DBInstanceIdentifier:
    type: String
    description: (Required) The DB Instance Identifier
  AlarmSnsTopic:
    type: String
    description: The SNS topic arn that we would like alarms to send notifications to.
    default: ${sns_topic_high}
mainSteps:
  - name: waitUntilMetricsAreStreaming
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3
        from datetime import datetime, timedelta
        from time import sleep


        def get_metric_stats(cloudwatch, db_instance_identifier, metric_name, namespace):
            response = cloudwatch.get_metric_statistics(
                Namespace=namespace,
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'DBInstanceIdentifier',
                        'Value': db_instance_identifier
                    },
                ],
                StartTime=datetime.utcnow() - timedelta(days=1),
                EndTime=datetime.utcnow(),
                Period=86400,
                Statistics=['Average']
            )
            if response['Datapoints']:
                return 'metrics are present'
            else:
                return ''


        def script_handler(events, context):
            cloudwatch = boto3.client('cloudwatch')
            db_instance_identifier = events['DBInstanceIdentifier']

            i = 0
            while True:
                read_metrics = get_metric_stats(cloudwatch, db_instance_identifier, 'FreeableMemory', 'AWS/RDS')
                if read_metrics:
                    break
                sleep(60)
                i += 1

            return 0
      InputPayload:
        DBInstanceIdentifier: '{{ DBInstanceIdentifier }}'
  - name: getDBInstance
    action: 'aws:executeAwsApi'
    onFailure: 'step:onFailure'
    inputs:
      Service: rds
      Api: DescribeDBInstances
      Filters:
        - Name: db-instance-id
          Values:
            - '{{ DBInstanceIdentifier }}'
    outputs:
      - Name: engine
        Selector: '$.DBInstances[0].Engine'
        Type: String
  - name: getAfterHourTag
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client
        rds = client("rds")


        def script_handler(events, context):
            db_id = events['db_id']
            after_hours = extract_after_hours_tag(get_all_rds_tags(compose_rds_arn(events['db_id'], events['sns_arn'])))
            return { 'AfterHourTag' : after_hours }


        def get_account_id(context):
            aws_account_id = context.split(":")[4]
            return aws_account_id


        def compose_rds_arn(db_id, sns_arn):
            return "arn:aws:rds:us-east-1:" + get_account_id(context=sns_arn) + ":db:" + db_id


        def get_all_rds_tags(db_arn):
            return rds.list_tags_for_resource(
                ResourceName=db_arn)['TagList']


        def extract_after_hours_tag(tag_list):
            after_hours = "NoTagAvailable"
            for i in tag_list:
                if i['Key'] == 'after-hours-support':
                    after_hours = i['Value']
            return after_hours
      InputPayload:
        db_id: '{{ DBInstanceIdentifier }}'
        sns_arn: '{{ AlarmSnsTopic }}'
    outputs:
      - Name: AfterHourTag
        Selector: '$.Payload.AfterHourTag'
        Type: String
  - name: chooseEngineForAlarms
    action: 'aws:branch'
    onFailure: 'step:onFailure'
    inputs:
      Choices:
        - NextStep: createStackOtherRDSEngines
          Not:
            Variable: '{{getDBInstance.engine}}'
            Contains: aurora
        - NextStep: createStackAuroraEngine
          Variable: '{{getDBInstance.engine}}'
          Contains: 'aurora'
      Default: onFailure
  - name: createStackOtherRDSEngines
    action: 'aws:createStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{DBInstanceIdentifier}}-alarms-stack'
      TemplateURL: 'https://${template_bucket}.s3.amazonaws.com/alarms-rds.yaml'
      Parameters:
        - ParameterValue: '{{DBInstanceIdentifier}}'
          ParameterKey: DBInstanceIdentifier
        - ParameterValue: '{{AlarmSnsTopic}}'
          ParameterKey: AlarmSnsTopic
        - ParameterValue: '${environment}'
          ParameterKey: Environment
        - ParameterValue: '{{getAfterHourTag.AfterHourTag}}'
          ParameterKey: AfterHourTag
    isEnd: true
  - name: createStackAuroraEngine
    action: 'aws:createStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{DBInstanceIdentifier}}-alarms-stack'
      TemplateURL: 'https://${template_bucket}.s3.amazonaws.com/alarms-rds-aurora.yaml'
      Parameters:
        - ParameterValue: '{{DBInstanceIdentifier}}'
          ParameterKey: DBInstanceIdentifier
        - ParameterValue: '{{AlarmSnsTopic}}'
          ParameterKey: AlarmSnsTopic
        - ParameterValue: '${environment}'
          ParameterKey: Environment
        - ParameterValue: '{{getAfterHourTag.AfterHourTag}}'
          ParameterKey: AfterHourTag
    isEnd: true
  - name: onFailure
    action: 'aws:executeScript'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3
        def script_handler(events, context):
            sns = boto3.client('sns')
            client = boto3.client('sts')
            account_id = client.get_caller_identity()["Account"]
            DBInstanceIdentifier = events['DBInstanceIdentifier']
            sns_topic_low = events['sns_topic_low']
            response = sns.publish(
               TopicArn=sns_topic_low,
               Message='Failed. The alarm can not be created for RDS ' + DBInstanceIdentifier + ' in account ' + account_id,
            )
      InputPayload:
        DBInstanceIdentifier: '{{DBInstanceIdentifier}}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true
