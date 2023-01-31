description: Create Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  HostId:
    type: String
    description: (Required) The ID of the host
  AlarmSnsTopic:
    type: String
    description: The SNS topic arn that we would like alarms to send notifications to.
    default: "/sns/dedicated-host-capacity-lambda"
mainSteps:
  - name: waitForCapacityMetrics
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3
        from datetime import datetime, timedelta
        from time import sleep


        def get_metric_stats(cloudwatch, host_id, metric_name, namespace):
            response = cloudwatch.get_metric_statistics(
                Namespace=namespace,
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'HostId',
                        'Value': host_id
                    }
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
            host_id = events['HostId']

            i = 0
            while i < 10:
                capacity_metrics = get_metric_stats(cloudwatch, host_id, 'AvailableCapacity', 'EC2 Dedicated Hosts')
                if capacity_metrics:
                    break
                sleep(60)
                i += 1
            return 0
      InputPayload:
        HostId: '{{HostId}}'
  - name: getSnsTopic
    action: 'aws:executeAwsApi'
    onFailure: 'step:onFailure'
    inputs:
      Service: ssm
      Api: GetParameter
      Name:
      - '{{AlarmSnsTopic}}'
    outputs:
      - Name: DedicatedHostSNS
        Selector: '$.Parameter.Value'
        Type: String
  - name: listInstanceTypeMetricsForHost
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client

        def script_handler(events,context):
            response = list_all_metrics_for_host(events['HostId'])
            if response['Metrics']:
                return { 'InstanceTypes': extract_instance_types_from_metrics(response)}
            else:
                return { 'InstanceTypes': []}


        def list_all_metrics_for_host(host_id):
            cloudwatch = client('cloudwatch')
            return cloudwatch.list_metrics(
                Namespace='EC2 Dedicated Hosts',
                Dimensions=[
                    {
                        'Name': 'HostId',
                        'Value': host_id
                    },
                ]
            )


        def extract_instance_types_from_metrics(response):
            instance_types: List[str] = []
            for metric in response['Metrics']:
                for dimension in metric['Dimensions']:
                    instance_types.append(dimension['Value'])
            return instance_types
      InputPayload:
        HostId: '{{HostId}}'
    outputs:
      - Name: InstanceTypes
        Selector: '$.Payload.InstanceTypes'
        Type: StringList
  - name: createStackForEachInstanceTypeOnHost
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client


        def script_handler(events, context):
            alarms_metadata = {
                'HostId': events['HostId'],
                'InstanceTypes': events['InstanceTypes'],
                'Environment': events['Environment'],
                'AvailableCapacityThreshold': events['AvailableCapacityThreshold'],
                'TemplateBucket': events['TemplateBucket']

            }

            created_alarms = create_alarms_stack_for_each_instance_type(
                alarms_metadata=alarms_metadata
            )

            return { 'CreatedAlarms': created_alarms }


        def create_alarms_stack_for_each_instance_type(alarms_metadata):
            cf = client('cloudformation')
            created_alarms = []
            for instance_type in alarms_metadata['InstanceTypes']:
                cf.create_stack(
                    StackName=f"{alarms_metadata['HostId']}-{instance_type}-alarms-stack",
                    TemplateURL=f"https://{alarms_metadata['TemplateBucket']}.s3.amazonaws.com/alarms-ec2-dedicated-host.yaml",
                    Parameters=[
                        {
                            'ParameterKey': 'HostId',
                            'ParameterValue': alarms_metadata['HostId']
                        },
                        {
                            'ParameterKey': 'InstanceType',
                            'ParameterValue': instance_type
                        },
                        {
                            'ParameterKey': 'Environment',
                            'ParameterValue': alarms_metadata['Environment']
                        }
                    ]
                )
                created_alarms.append(
                    f"{alarms_metadata['Environment']}"
                    f"-{alarms_metadata['HostId']}"
                    f"-{alarms_metadata['InstanceType']}"
                    f"-Capacity-Alarm")

            return created_alarms
      InputPayload:
        HostId: '{{HostId}}'
        InstanceTypes: '{{listInstanceTypeMetricsForHost.InstanceTypes}}'
        Environment: '${environment}'
        TemplateBucket: '${template_bucket}'
    outputs:
      - Name: CreatedAlarms
        Selector: '$.Payload.CreatedAlarms'
        Type: StringList
  - name: createOrUpdateCompositeCapacityAlarm
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from typing import List

        from boto3 import client


        def script_handler(events, context):
            cw = client('cloudwatch')
            sns_topic = events['AlarmSnsTopic']
            created_alarms = events['CreatedAlarms']
            for alarm in created_alarms:
                add_alarm_under_a_composite_capacity_alarm(alarm, cw, sns_topic)


        def add_alarm_under_a_composite_capacity_alarm(alarm, cw, sns_topic):
            alarm_metadata = alarm.split('-')
            if alarm_metadata:
                instance_type = alarm_metadata[2]
                update_composite_capacity_alarm(
                    cw=cw,
                    instance_type=instance_type,
                    sns_topic=sns_topic,
                    alarm_rule=" AND ".join(get_all_alarms_for_one_instance_type(alarm_metadata, cw, instance_type))

                )


        def update_composite_capacity_alarm(cw, instance_type, sns_topic, alarm_rule):
            cw.put_composite_alarm(
                ActionsEnabled=True,
                AlarmActions=[
                    sns_topic,
                ],
                AlarmDescription=f'Available capacity for instance type {instance_type} on dedicated hosts',
                AlarmName=f'{instance_type}-Available-Capacity',
                AlarmRule=alarm_rule,
                InsufficientDataActions=[
                    sns_topic,
                ],
                OKActions=[
                    sns_topic,
                ]
            )


        def get_all_alarms_for_one_instance_type(alarm_metadata, cw, instance_type):
            environment = alarm_metadata[0]
            dedicated_host_alarms = cw.describe_alarms(
                AlarmNames=[compose_possible_alarm_names_for_instance_type(environment, instance_type)]
            )
            dedicated_host_alarm_names = extract_alarm_names_from_dedicated_host_alarms(dedicated_host_alarms)
            return dedicated_host_alarm_names


        def compose_possible_alarm_names_for_instance_type(environment, instance_type):
            composed_alarms_names = []
            for host_id in get_dedicated_hosts_ids():
                composed_alarms_names.append(f"{environment}-{host_id}-{instance_type}-Capacity-Alarm")
            return composed_alarms_names


        def extract_alarm_names_from_dedicated_host_alarms(dedicated_host_alarms):
            dedicated_host_alarm_names = []
            for dedicated_host_alarm in dedicated_host_alarms['MetricAlarms']:
                dedicated_host_alarm_names.append(f"ALARM({dedicated_host_alarm['AlarmName']})")
            return dedicated_host_alarm_names


        def get_dedicated_hosts_ids():
            ec2 = client('ec2')
            dedicated_hosts_ids: List[str] = []
            for host in ec2.describe_hosts()['Hosts']:
                dedicated_hosts_ids.append(host['HostId'])
            return dedicated_hosts_ids

      InputPayload:
        CreatedAlarms: '{{createStackForEachInstanceTypeOnHost.CreatedAlarms}}'
        AlarmSnsTopic: '{{getSnsTopic.DedicatedHostSNS}}'
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
            host_id = events['HostId']
            sns_topic_low = events['sns_topic_low']
            response = sns.publish(
               TopicArn=sns_topic_low,
               Message='Failed. The alarm can not be created for host ' + host_id + ' in account ' + account_id,
            )
      InputPayload:
        HostId: '{{HostId}}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true
