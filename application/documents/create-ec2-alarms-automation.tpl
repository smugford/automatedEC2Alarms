description: Create Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  InstanceId:
    type: String
    description: (Required) The ID of the instance
mainSteps:
  - name: waitForStatusChecks
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3
        from datetime import datetime, timedelta
        from time import sleep


        def get_metric_stats(cloudwatch, instance_id, metric_name, namespace):
            response = cloudwatch.get_metric_statistics(
                Namespace=namespace,
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': instance_id
                    },
                ],
                StartTime=datetime.utcnow() - timedelta(hours=3),
                EndTime=datetime.utcnow(),
                Period=10800,
                Statistics=['Average']
            )
            if response['Datapoints']:
                return 'metrics are present'
            else:
                return ''


        def script_handler(events, context):
            cloudwatch = boto3.client('cloudwatch')
            instance_id = events['InstanceId']

            i = 0
            while i < 10:
                status_check = get_metric_stats(cloudwatch, instance_id, 'StatusCheckFailed', 'AWS/EC2')
                if status_check:
                    break
                sleep(60)
                i += 1
            return 0
      InputPayload:
        InstanceId: '{{ InstanceId }}'
  - name: getInstance
    action: 'aws:executeAwsApi'
    onFailure: 'step:onFailure'
    inputs:
      Service: ssm
      Api: DescribeInstanceInformation
      Filters:
        - Key: InstanceIds
          Values:
            - '{{ InstanceId }}'
    outputs:
      - Name: platform
        Selector: '$.InstanceInformationList[0].PlatformType'
        Type: String
  - name: getInstanceName
    action: 'aws:executeAwsApi'
    onFailure: 'step:onFailure'
    inputs:
      Service: ec2
      Api: DescribeTags
      Filters:
        - Name: resource-id
          Values:
           - '{{ InstanceId }}'
        - Name: key
          Values:
           - 'Name'
    outputs:
      - Name: InstanceName
        Selector: '$.Tags[0].Value'
        Type: String
  - name: getAfterHourTag
    action: 'aws:executeAwsApi'
    onFailure: 'step:onFailure'
    inputs:
      Service: ec2
      Api: DescribeTags
      Filters:
        - Name: resource-id
          Values:
           - '{{ InstanceId }}'
        - Name: key
          Values:
           - 'after-hours-support'
    outputs:
      - Name: AfterHourTag
        Selector: '$.Tags[0].Value'
        Type: String
  - name: getMetricStatistics
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3
        from datetime import datetime, timedelta

        def get_metric_stats(cloudwatch, instance_id, metric_name, namespace):
          response = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=[
              {
                'Name': 'InstanceId',
                'Value': instance_id
              },
            ],
            StartTime=datetime.utcnow() - timedelta(days=1),
            EndTime=datetime.utcnow(),
            Period=86400,
            Statistics=['Average']
          )
          if response['Datapoints']:
            if response['Datapoints'][0]['Average'] >= 85:
                return '95'
            return '90'
          else:
            return '0'

        def script_handler(events, context):
           cloudwatch  = boto3.client('cloudwatch')
           instance_id = events['InstanceId']

           mem_metric_name = 'mem_used_percent'
           if events['Platform'] == 'Windows':
              mem_metric_name = 'Memory % Committed Bytes In Use'

           cpu_results = get_metric_stats(cloudwatch, instance_id, 'CPUUtilization', 'AWS/EC2')
           mem_results = get_metric_stats(cloudwatch, instance_id, mem_metric_name, 'CWAgent')

           return { 'CPUThreshold' : cpu_results, 'MemoryThreshold' : mem_results }
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        Platform: '{{getInstance.platform}}'
    outputs:
      - Name: CPUThreshold
        Selector: '$.Payload.CPUThreshold'
        Type: String
      - Name: MemoryThreshold
        Selector: '$.Payload.MemoryThreshold'
        Type: String
  - name: chooseOSForCommands
    action: 'aws:branch'
    onFailure: 'step:onFailure'
    inputs:
      Choices:
        - NextStep: createStackWindows
          Variable: '{{getInstance.platform}}'
          StringEquals: Windows
        - NextStep: createStackLinux
          Variable: '{{getInstance.platform}}'
          StringEquals: Linux
      Default: createStackOSUnknown
  - name: createStackOSUnknown
    action: 'aws:createStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{InstanceId}}-alarms-stack'
      TemplateURL: 'https://${template_bucket}.s3.amazonaws.com/alarms-ec2-os-unknown.yaml'
      Parameters:
        - ParameterValue: '{{InstanceId}}'
          ParameterKey: InstanceId
        - ParameterValue: '${sns_topic_high}'
          ParameterKey: AlarmSnsTopic
        - ParameterValue: '${environment}'
          ParameterKey: Environment
        - ParameterValue: '{{getAfterHourTag.AfterHourTag}}'
          ParameterKey: AfterHourTag
        - ParameterValue: '{{getInstanceName.InstanceName}}'
          ParameterKey: InstanceName
        - ParameterValue: '${application}'
          ParameterKey: ApplicationName
        - ParameterValue: '${application_runbook_url}'
          ParameterKey: ApplicationRunbookUrl
    isEnd: true
  - name: createStackWindows
    action: 'aws:createStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{InstanceId}}-alarms-stack'
      TemplateURL: 'https://${template_bucket}.s3.amazonaws.com/alarms-ec2-windows.yaml'
      Parameters:
        - ParameterValue: '{{InstanceId}}'
          ParameterKey: InstanceId
        - ParameterValue: '${sns_topic_high}'
          ParameterKey: AlarmSnsTopic
        - ParameterValue: '${environment}'
          ParameterKey: Environment
        - ParameterValue: '{{getAfterHourTag.AfterHourTag}}'
          ParameterKey: AfterHourTag
        - ParameterValue: '{{getMetricStatistics.CPUThreshold}}'
          ParameterKey: CPUThreshold
        - ParameterValue: '{{getMetricStatistics.MemoryThreshold}}'
          ParameterKey: MemoryThreshold
        - ParameterValue: '{{getInstanceName.InstanceName}}'
          ParameterKey: InstanceName
    nextStep: createWindowsDiskAlarms
  - name: createStackLinux
    action: 'aws:createStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{InstanceId}}-alarms-stack'
      TemplateURL: 'https://${template_bucket}.s3.amazonaws.com/alarms-ec2-linux.yaml'
      Parameters:
        - ParameterValue: '{{InstanceId}}'
          ParameterKey: InstanceId
        - ParameterValue: '${sns_topic_high}'
          ParameterKey: AlarmSnsTopic
        - ParameterValue: '${environment}'
          ParameterKey: Environment
        - ParameterValue: '{{getAfterHourTag.AfterHourTag}}'
          ParameterKey: AfterHourTag
        - ParameterValue: '{{getMetricStatistics.CPUThreshold}}'
          ParameterKey: CPUThreshold
        - ParameterValue: '{{getMetricStatistics.MemoryThreshold}}'
          ParameterKey: MemoryThreshold
        - ParameterValue: '{{getInstanceName.InstanceName}}'
          ParameterKey: InstanceName
    nextStep: createLinuxDiskAlarms
  - name: createLinuxDiskAlarms
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        def get_metrics(cloudwatch, InstanceId):
            response = cloudwatch.list_metrics(
                Namespace='CWAgent',
                MetricName='disk_used_percent',
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': InstanceId
                    }
                ],
                RecentlyActive='PT3H'
            )
            devices = []
            for i in range(0, len(response['Metrics'])):
                for b in range(0, len(response['Metrics'][i]['Dimensions'])):
                    if 'device' in response['Metrics'][i]['Dimensions'][b]['Name']:
                        devices.append(response['Metrics'][i]['Dimensions'][b]['Value'])
            sorted = list(dict.fromkeys(devices))
            return(sorted)
        def create_alarms(cloudwatch, devices, InstanceId, sns_topic_high, AfterHourTag, Environment, Aws_Region, AccountId, InstanceName):
            for device in devices:
                print('creating linux disk alarm for...' + device)
                cloudwatch.put_metric_alarm(
                    AlarmName=Environment + '-' + InstanceId + '-LinuxDiskFreeSpace-' + device,
                    ComparisonOperator='GreaterThanThreshold',
                    EvaluationPeriods=5,
                    MetricName='disk_used_percent',
                    Namespace='CWAgent',
                    Period=60,
                    Statistic='Average',
                    Threshold=90,
                    ActionsEnabled=True,
                    TreatMissingData='breaching',
                    AlarmDescription= """{\"region\":\"%s\",\"description\":\"Used Disk Space above 90 percent\"
                                         ,\"environment\":\"%s\",\"account_id\":\"%s\",\"type\":\"EC2\"
                                         ,\"instance name\":\"%s\",\"after-hours-support\":\"%s\"}""" \
                                         % (Aws_Region, Environment, AccountId, InstanceName, AfterHourTag),
                    AlarmActions=[sns_topic_high],
                    OKActions=[sns_topic_high],
                    Dimensions=[
                        {
                        'Name': 'InstanceId',
                        'Value': InstanceId
                        },
                        {
                        'Name': 'device',
                        'Value': device
                        }
                    ]
                )

        def script_handler(events, context):
           import boto3
           cloudwatch    = boto3.client('cloudwatch')

           InstanceId = events['InstanceId']
           AfterHourTag = events['AfterHourTag']
           sns_topic_high = events['sns_topic_high']
           Environment = events['Environment']
           Aws_Region = events['Aws_Region']
           AccountId = sns_topic_high.split(':')[4]
           InstanceName = events['InstanceName']

           devices = get_metrics(cloudwatch, InstanceId)
           create_alarms(cloudwatch, devices, InstanceId, sns_topic_high, AfterHourTag, Environment, Aws_Region, AccountId, InstanceName)
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        AfterHourTag: '{{ getAfterHourTag.AfterHourTag }}'
        sns_topic_high: '${sns_topic_high}'
        Environment: '${environment}'
        Aws_Region: '${aws_region}'
        InstanceName: '{{getInstanceName.InstanceName}}'
    isEnd: true
  - name: createWindowsDiskAlarms
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        def get_metrics(cloudwatch, InstanceId):
            response = cloudwatch.list_metrics(
                Namespace='CWAgent',
                MetricName='LogicalDisk % Free Space',
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': InstanceId
                    }
                ],
                RecentlyActive='PT3H'
            )
            disk = []
            for i in range(0, len(response['Metrics'])):
                 for b in range(0, len(response['Metrics'][i]['Dimensions'])):
                     if 'instance' in response['Metrics'][i]['Dimensions'][b]['Name']:
                         disk.append(response['Metrics'][i]['Dimensions'][b]['Value'])
            sorted = list(dict.fromkeys(disk))
            return sorted
        def create_alarms(cloudwatch, devices, InstanceId, sns_topic_high, AfterHourTag, Environment, Aws_Region, AccountId, InstanceName):
            for device in devices:
                print('creating windows disk alarm for...' + device)
                cloudwatch.put_metric_alarm(
                    AlarmName=Environment + '-' + InstanceId + '-WindowsDiskFreeSpace-' + device,
                    ComparisonOperator='LessThanThreshold',
                    EvaluationPeriods=5,
                    MetricName='LogicalDisk % Free Space',
                    Namespace='CWAgent',
                    Period=60,
                    Statistic='Average',
                    Threshold=15,
                    ActionsEnabled=True,
                    TreatMissingData='breaching',
                    AlarmActions=[sns_topic_high],
                    OKActions=[sns_topic_high],
                    AlarmDescription= """{\"region\":\"%s\",\"description\":\"Used Disk Space above 90 percent\"
                                         ,\"environment\":\"%s\",\"account_id\":\"%s\",\"type\":\"EC2\"
                                         ,\"instance_name\":\"%s\",\"after-hours-support\":\"%s\"}""" \
                                         % (Aws_Region, Environment, AccountId, InstanceName, AfterHourTag),
                    Dimensions=[
                        {
                        'Name': 'InstanceId',
                        'Value': InstanceId
                        },
                        {
                        'Name': 'instance',
                        'Value': device
                        }
                    ]
                )

        def script_handler(events, context):
           import boto3
           cloudwatch    = boto3.client('cloudwatch')

           InstanceId = events['InstanceId']
           AfterHourTag = events['AfterHourTag']
           sns_topic_high = events['sns_topic_high']
           Environment = events['Environment']
           Aws_Region = events['Aws_Region']
           AccountId = sns_topic_high.split(':')[4]
           InstanceName = events['InstanceName']

           devices = get_metrics(cloudwatch, InstanceId)
           create_alarms(cloudwatch, devices, InstanceId, sns_topic_high, AfterHourTag, Environment, Aws_Region, AccountId, InstanceName)
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        AfterHourTag: '{{ getAfterHourTag.AfterHourTag }}'
        sns_topic_high: '${sns_topic_high}'
        Environment: '${environment}'
        Aws_Region: '${aws_region}'
        InstanceName: '{{getInstanceName.InstanceName}}'
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
            InstanceId = events['InstanceId']
            sns_topic_low = events['sns_topic_low']
            response = sns.publish(
               TopicArn=sns_topic_low,
               Message='Failed. The alarm can not be created for instance ' + InstanceId + ' in account ' + account_id,
            )
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true
