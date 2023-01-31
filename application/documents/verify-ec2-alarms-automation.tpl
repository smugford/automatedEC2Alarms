description: Verify Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  InstanceId:
    type: String
    description: (Optional) The ID of the instance
    default: ''
mainSteps:
  - name: getInstance
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from typing import Dict

        from boto3 import client


        def script_handler(events, context):
            if instance_id_is_passed(events):
                return get_platform_of_one_instance(events)
            else:
                return get_platform_of_all_instances()


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def get_platform_of_one_instance(events):
            ssm = client('ssm')
            alarms_metadata: Dict[str, Dict[str, str]] = {}
            instance = ssm.describe_instance_information(
                Filters=[
                    {
                        'Key': 'InstanceIds',
                        'Values': [events['InstanceId']]
                    }
                ]
            )['InstanceInformationList'][0]
            store_instance_platform_to_alarms_metadata(alarms_metadata, instance)
            return alarms_metadata


        def get_platform_of_all_instances():
            ssm = client('ssm')
            alarms_metadata: Dict[str, Dict[str, str]] = {}
            paginator = ssm.get_paginator('describe_instance_information')
            instances = paginator.paginate().build_full_result()
            for instance in instances['InstanceInformationList']:
                store_instance_platform_to_alarms_metadata(alarms_metadata, instance)
            return alarms_metadata


        def store_instance_platform_to_alarms_metadata(alarms_metadata, instance):
            alarms_metadata.setdefault(instance['InstanceId'], {'Platform': get_instance_platform(instance)})


        def get_instance_platform(instance):
            return instance['PlatformType'] if 'PlatformType' in instance else ''
      InputPayload:
        InstanceId: '{{ InstanceId }}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: getInstanceName
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client


        def script_handler(events, context):
            if instance_id_is_passed(events):
                return get_name_of_one_instance(events)
            else:
                return get_name_of_all_instances(events)


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def get_name_of_one_instance(events):
            ec2 = client('ec2')
            instance_id = events['InstanceId']
            alarms_metadata = events['AlarmsMetadata']
            alarms_metadata[instance_id]['Name'] = get_instance_name_from_tag(ec2, instance_id)
            return alarms_metadata


        def get_name_of_all_instances(events):
            ec2 = client('ec2')
            alarms_metadata = events['AlarmsMetadata']
            for instance in alarms_metadata:
                alarms_metadata[instance]['Name'] = get_instance_name_from_tag(ec2, instance)
            return alarms_metadata


        def get_instance_name_from_tag(ec2, instance_id):
            return ec2.describe_tags(
                Filters=[
                    {'Name': 'resource-id', 'Values': [instance_id]}, {'Name': 'key', 'Values': ['Name']}
                ]
            )['Tags'][0]['Value']

      InputPayload:
        InstanceId: '{{InstanceId}}'
        AlarmsMetadata: '{{getInstance.AlarmsMetadata}}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: getAfterHourTag
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client


        def script_handler(events, context):
            if instance_id_is_passed(events):
                return get_after_hours_tag_of_one_instance(events)
            else:
                return get_after_hours_tag_of_all_instances(events)


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def get_after_hours_tag_of_one_instance(events):
            ec2 = client('ec2')
            instance_id = events['InstanceId']
            alarms_metadata = events['AlarmsMetadata']
            store_after_hours_tag(alarms_metadata, ec2, instance_id)
            return alarms_metadata


        def get_after_hours_tag_of_all_instances(events):
            ec2 = client('ec2')
            alarms_metadata = events['AlarmsMetadata']
            for instance_id in alarms_metadata:
                store_after_hours_tag(alarms_metadata, ec2, instance_id)
            return alarms_metadata


        def store_after_hours_tag(alarms_metadata, ec2, instance_id):
            alarms_metadata[instance_id]['after-hours-support'] = get_after_hours_tag_value_for_instance(ec2, instance_id)


        def get_after_hours_tag_value_for_instance(ec2, instance_id):
            tags = ec2.describe_tags(
                Filters=[
                    {'Name': 'resource-id', 'Values': [instance_id]}, {'Name': 'key', 'Values': ['after-hours-support']}
                ]
            )['Tags']
            if tags:
                first_tag = tags[0]
                if 'Value' in first_tag and first_tag['Value']:
                    return first_tag['Value']
            return 'NoTagAvailable'

      InputPayload:
        InstanceId: '{{InstanceId}}'
        AlarmsMetadata: '{{getInstanceName.AlarmsMetadata}}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: getMetricStatistics
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client
        from datetime import datetime, timedelta


        def script_handler(events, context):
            if instance_id_is_passed(events):
                return compute_metrics_thresholds_for_one_instance(events)
            else:
                return compute_metrics_thresholds_for_all_instances(events)


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def compute_metrics_thresholds_for_one_instance(events):
            instance_id = events['InstanceId']
            alarms_metadata = events['AlarmsMetadata']
            platform_type = alarms_metadata[instance_id]['Platform']

            cloudwatch = client('cloudwatch')
            store_metrics_thresholds(alarms_metadata, cloudwatch, instance_id, platform_type)
            return alarms_metadata


        def compute_metrics_thresholds_for_all_instances(events):
            alarms_metadata = events['AlarmsMetadata']
            cloudwatch = client('cloudwatch')
            for instance_id in alarms_metadata:
                platform_type = events['AlarmsMetadata'][instance_id]['Platform']
                store_metrics_thresholds(alarms_metadata, cloudwatch, instance_id, platform_type)
            return alarms_metadata


        def store_metrics_thresholds(alarms_metadata, cloudwatch, instance_id, platform_type):
            mem_metric_name = set_memory_metric_name_based_on_platform(platform_type)

            cpu_results = get_metric_stats(cloudwatch, instance_id, 'CPUUtilization', 'AWS/EC2')
            mem_results = get_metric_stats(cloudwatch, instance_id, mem_metric_name, 'CWAgent')

            alarms_metadata[instance_id]['CPUThreshold'] = cpu_results
            alarms_metadata[instance_id]['MemoryThreshold'] = mem_results


        def set_memory_metric_name_based_on_platform(platform_type):
            if platform_type == 'Windows':
                return 'Memory % Committed Bytes In Use'
            return 'mem_used_percent'


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
                    return '95.0'
                return '90.0'
            else:
                return '0'

      InputPayload:
        InstanceId: '{{InstanceId}}'
        AlarmsMetadata: '{{getAfterHourTag.AlarmsMetadata}}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: storeStandardAlarmConfigsBasedOnPlatform
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        def script_handler(events, context):
            if instance_id_is_passed(events):
                return get_alarms_created_with_cloudformation_for_one_instance(events, context)
            else:
                return get_alarms_created_with_cloudformation_for_all_instances(events, context)


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def get_alarms_created_with_cloudformation_for_one_instance(events, context):
            instance_id = events['InstanceId']
            alarms_metadata = events['AlarmsMetadata']
            store_alarms_configs_based_on_platform(alarms_metadata, context, events, instance_id)
            return alarms_metadata


        def get_alarms_created_with_cloudformation_for_all_instances(events, context):
            alarms_metadata = events['AlarmsMetadata']
            for instance_id in alarms_metadata:
                store_alarms_configs_based_on_platform(alarms_metadata, context, events, instance_id)
            return alarms_metadata


        def store_alarms_configs_based_on_platform(alarms_metadata, context, events, instance_id):
            platform_type = alarms_metadata[instance_id]['Platform']
            if platform_type == "Windows":
                store_alarms_configs_for_windows(instance_id, alarms_metadata, events, context)
            elif platform_type == "Linux":
                store_alarms_configs_for_linux(instance_id, alarms_metadata, events, context)
            else:
                store_alarms_configs_for_unknown_os(instance_id, alarms_metadata, events, context)


        def store_alarms_configs_for_windows(instance_id, alarms_metadata, events, context):
            alarm_configs = [
                {
                    'AlarmName': f"{events['Environment']}-{instance_id}-CPUUtilization-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "EC2 CPUUtilization Alarm",
                        "alarm_name": "CPUUtilization-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'CPUUtilization',
                    'Statistic': 'Average',
                    'Period': '300',
                    'EvaluationPeriods': '4',
                    'Threshold': f"{alarms_metadata[instance_id]['CPUThreshold']}",
                    'ComparisonOperator': 'GreaterThanThreshold',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{instance_id}-StatusCheckFailed-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "EC2 StatusCheckFail",
                        "alarm_name": "StatusCheckFailed-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'StatusCheckFailed',
                    'Statistic': 'Minimum',
                    'Period': '300',
                    'EvaluationPeriods': '5',
                    'Threshold': '1.0',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                    'TreatMissingData': 'breaching'
                }]
            if alarms_metadata[instance_id]['MemoryThreshold'] != '0':
                alarm_configs.append(
                    {
                        'AlarmName': f"{events['Environment']}-{instance_id}-MemoryUtilization-Alarm",
                        'ActionsEnabled': True,
                        'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                        'OKActions': [f"{events['AlarmSnsTopic']}"],
                        'AlarmDescription': {
                            "region": f"{context.get('global:REGION')}",
                            "description": "EC2 Memory Alarm",
                            "alarm_name": "Memory-Alarm",
                            "environment": f"{events['Environment']}",
                            "account_id": f"{context.get('global:ACCOUNT_ID')}",
                            "type": "EC2",
                            "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                            "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                        },
                        'Namespace': 'CWAgent',
                        'MetricName': 'Memory % Committed Bytes In Use',
                        'Statistic': 'Average',
                        'Period': '300',
                        'EvaluationPeriods': '4',
                        'Threshold': f"{alarms_metadata[instance_id]['MemoryThreshold']}",
                        'ComparisonOperator': 'GreaterThanThreshold',
                        'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                        'TreatMissingData': 'breaching'
                    })
            alarms_metadata[instance_id]['AlarmConfigs'] = alarm_configs


        def store_alarms_configs_for_linux(instance_id, alarms_metadata, events, context):
            alarm_configs = [
                {
                    'AlarmName': f"{events['Environment']}-{instance_id}-CPUUtilization-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "EC2 Linux CPUUtilization Alarm",
                        "alarm_name": "CPUUtilization-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'CPUUtilization',
                    'Statistic': 'Average',
                    'Period': '300',
                    'EvaluationPeriods': '5',
                    'Threshold': f"{alarms_metadata[instance_id]['CPUThreshold']}",
                    'ComparisonOperator': 'GreaterThanThreshold',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{instance_id}-StatusCheckFailed-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "EC2 Linux StatusCheckFail",
                        "alarm_name": "StatusCheckFailed-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'StatusCheckFailed',
                    'Statistic': 'Minimum',
                    'Period': '300',
                    'EvaluationPeriods': '5',
                    'Threshold': '1.0',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                    'TreatMissingData': 'breaching'
                }]
            if alarms_metadata[instance_id]['MemoryThreshold'] != '0':
                alarm_configs.append(
                    {
                        'AlarmName': f"{events['Environment']}-{instance_id}-MemoryUtilization-Alarm",
                        'ActionsEnabled': True,
                        'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                        'OKActions': [f"{events['AlarmSnsTopic']}"],
                        'AlarmDescription': {
                            "region": f"{context.get('global:REGION')}",
                            "description": "EC2 Linux Memory Alarm",
                            "alarm_name": "Memory-Alarm",
                            "environment": f"{events['Environment']}",
                            "account_id": f"{context.get('global:ACCOUNT_ID')}",
                            "type": "EC2",
                            "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                            "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                        },
                        'Namespace': 'CWAgent',
                        'MetricName': 'mem_used_percent',
                        'Statistic': 'Average',
                        'Period': '300',
                        'EvaluationPeriods': '5',
                        'Threshold': f"{alarms_metadata[instance_id]['MemoryThreshold']}",
                        'ComparisonOperator': 'GreaterThanThreshold',
                        'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                        'TreatMissingData': 'breaching'
                    })
                alarm_configs.append(
                    {
                        'AlarmName': f"{events['Environment']}-{instance_id}-SwapSpace-Alarm",
                        'ActionsEnabled': True,
                        'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                        'OKActions': [f"{events['AlarmSnsTopic']}"],
                        'AlarmDescription': {
                            "region": f"{context.get('global:REGION')}",
                            "description": "EC2 Linux Swap Alarm",
                            "alarm_name": "Swap-Alarm",
                            "environment": f"{events['Environment']}",
                            "account_id": f"{context.get('global:ACCOUNT_ID')}",
                            "type": "EC2",
                            "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                            "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                        },
                        'Namespace': 'CWAgent',
                        'MetricName': 'swap_used_percent',
                        'Statistic': 'Average',
                        'Period': '300',
                        'EvaluationPeriods': '5',
                        'Threshold': '50.0',
                        'ComparisonOperator': 'GreaterThanThreshold',
                        'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                        'TreatMissingData': 'breaching'
                    })
            alarms_metadata[instance_id]['AlarmConfigs'] = alarm_configs


        def store_alarms_configs_for_unknown_os(instance_id, alarms_metadata, events, context):
            alarm_configs = [
                {
                    'AlarmName': f"{events['Environment']}-{instance_id}-CPUUtilization-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "EC2 CPUUtilization Alarm",
                        "alarm_name": "CPUUtilization-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'CPUUtilization',
                    'Statistic': 'Average',
                    'Period': '300',
                    'EvaluationPeriods': '4',
                    'Threshold': '90.0',
                    'ComparisonOperator': 'GreaterThanThreshold',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{instance_id}-StatusCheckFailed-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "EC2 StatusCheckFail",
                        "alarm_name": "StatusCheckFailed-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/EC2',
                    'MetricName': 'StatusCheckFailed',
                    'Statistic': 'Minimum',
                    'Period': '300',
                    'EvaluationPeriods': '5',
                    'Threshold': '1.0',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': f'{instance_id}'}],
                    'TreatMissingData': 'breaching'
                }
            ]
            alarms_metadata[instance_id]['AlarmConfigs'] = alarm_configs

      InputPayload:
        InstanceId: '{{InstanceId}}'
        AlarmsMetadata: '{{getMetricStatistics.AlarmsMetadata}}'
        Environment: '${environment}'
        AlarmSnsTopic: '${sns_topic_high}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: appendDiskAlarmsConfigs
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client


        def script_handler(events, context):
            if instance_id_is_passed(events):
                return get_disk_alarms_for_one_instance(events, context)
            else:
                return get_disk_alarms_for_all_instances(events, context)


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def get_disk_alarms_for_one_instance(events, context):
            cloudwatch = client('cloudwatch')
            instance_id = events['InstanceId']
            sns_topic = events['AlarmSnsTopic']
            devices = get_metrics(cloudwatch, instance_id, events)
            append_disk_alarms_configs(events, context, devices, instance_id, sns_topic)
            return events['AlarmsMetadata']


        def get_disk_alarms_for_all_instances(events, context):
            cloudwatch = client('cloudwatch')
            sns_topic = events['AlarmSnsTopic']
            alarms_metadata = events['AlarmsMetadata']
            for instance_id in alarms_metadata:
                devices = get_metrics(cloudwatch, instance_id, events)
                append_disk_alarms_configs(events, context, devices, instance_id, sns_topic)
            return events['AlarmsMetadata']


        def get_metrics(cloudwatch, instance_id, events):
            alarms_metadata = events['AlarmsMetadata']
            metric = 'LogicalDisk % Free Space' if instance_is_windows(alarms_metadata, instance_id) else 'disk_used_percent'
            dimension = 'instance' if instance_is_windows(alarms_metadata, instance_id) else 'device'
            response = cloudwatch.list_metrics(
                Namespace='CWAgent',
                MetricName=metric,
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': instance_id
                    }
                ],
                RecentlyActive='PT3H'
            )
            storage = []
            for i in range(0, len(response['Metrics'])):
                for b in range(0, len(response['Metrics'][i]['Dimensions'])):
                    if dimension in response['Metrics'][i]['Dimensions'][b]['Name']:
                        storage.append(response['Metrics'][i]['Dimensions'][b]['Value'])
            return list(dict.fromkeys(storage))


        def append_disk_alarms_configs(events, context, devices, instance_id, sns_topic):
            alarms_metadata = events['AlarmsMetadata']
            comp_operator = 'LessThanThreshold' if instance_is_windows(alarms_metadata, instance_id) else 'GreaterThanThreshold'
            metric = 'LogicalDisk % Free Space' if instance_is_windows(alarms_metadata, instance_id) else 'disk_used_percent'
            dimension = 'instance' if instance_is_windows(alarms_metadata, instance_id) else 'device'
            threshold = '15.0' if instance_is_windows(alarms_metadata, instance_id) else '90.0'
            platform = alarms_metadata[instance_id]['Platform']

            for device in devices:
                alarms_config = {
                    'AlarmName': f"{events['Environment']}-{instance_id}-{platform}DiskFreeSpace-{device}",
                    'ComparisonOperator': comp_operator,
                    'EvaluationPeriods': '5',
                    'MetricName': metric,
                    'Namespace': 'CWAgent',
                    'Period': '60',
                    'Statistic': 'Average',
                    'Threshold': threshold,
                    'ActionsEnabled': True,
                    'TreatMissingData': 'breaching',
                    'AlarmActions': [sns_topic],
                    'OKActions': [sns_topic],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "Used Disk Space above 90 percent",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "EC2",
                        "instance_name": f"{alarms_metadata[instance_id]['Name']}",
                        "after-hours-support": f"{alarms_metadata[instance_id]['after-hours-support']}"
                    },
                    'Dimensions': [
                        {
                            'Name': 'InstanceId',
                            'Value': instance_id
                        },
                        {
                            'Name': dimension,
                            'Value': device
                        }
                    ]
                }
                alarms_metadata[instance_id]['AlarmConfigs'].append(alarms_config)


        def instance_is_windows(alarms_metadata, instance_id):
            return alarms_metadata[instance_id]['Platform'] == "Windows"

      InputPayload:
        InstanceId: '{{InstanceId}}'
        AlarmsMetadata: '{{storeStandardAlarmConfigsBasedOnPlatform.AlarmsMetadata}}'
        Environment: '${environment}'
        AlarmSnsTopic: '${sns_topic_high}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: verifyAlarms
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client
        from json import loads


        def script_handler(events, context):
            if instance_id_is_passed(events):
                return verify_alarms_for_one_instance(events)
            else:
                return verify_alarms_for_all_instances(events, context)


        def instance_id_is_passed(events):
            return 'InstanceId' in events and events['InstanceId']


        def verify_alarms_for_one_instance(events):
            cw = client('cloudwatch')
            instance_id = events['InstanceId']
            verifier_output = verify_one_instance(cw, events, instance_id)
            return {"BAM Verifier Output": verifier_output}


        def verify_alarms_for_all_instances(events, context):
            cw = client('cloudwatch')
            alarms_metadata = events['AlarmsMetadata']
            verifier_output = {}
            for instance_id in alarms_metadata:
                verifier_output[instance_id] = verify_one_instance(cw,events,instance_id)
            return {"BAM Verifier Output": verifier_output}


        def verify_one_instance(cw, events, instance_id):
            actual_instance_alarms = get_all_alarms_for_instance_id(cw, instance_id, events)
            expected_instance_alarms = events['AlarmsMetadata'][instance_id]['AlarmConfigs']
            verifier_output = ""
            for expected_alarm in expected_instance_alarms:
                actual_alarm = get_alarm(expected_alarm, actual_instance_alarms)
                if actual_alarm:
                    verifier_output += compare_alarm_configs(expected_alarm, actual_alarm, expected_alarm["AlarmName"])
                else:
                    verifier_output += f"Missing: {expected_alarm['AlarmName']}\n"
            return verifier_output


        def get_all_alarms_for_instance_id(cw, instance_id, events):
            list_response = cw.describe_alarms(
                AlarmNamePrefix=f"{events['Environment']}-{instance_id}",
                AlarmTypes=['MetricAlarm']
            )['MetricAlarms']
            for item in list_response:
                reformat(item)
            return list_response


        def reformat(actual):
            for key in actual:
                if type(actual[key]).__name__ == 'datetime':
                    actual[key] = str(actual[key])
            return actual


        def get_alarm(alarm_config, list_of_actual_alarm_configs):
            for item in list_of_actual_alarm_configs:
                if item["AlarmName"] == alarm_config["AlarmName"]:
                    return item
            return {}


        def compare_alarm_configs(expected, actual, name):
            compare_output = ""
            for key in expected:
                if key in actual:
                    if type(expected[key]).__name__ == 'dict':
                        compare_output += "" + compare_alarm_configs(expected[key], loads(actual[key]), name)
                    else:
                        actual_value = str(actual[key])
                        if str(expected[key]).strip() != str(actual_value).strip():
                            compare_output += f"Diff: {name} / {key}\n" \
                                              f"Expected: {expected[key]}\n" \
                                              f"Actual: {actual_value}\n"
                else:
                    compare_output += f"Missing: {name} / {key}"
            return compare_output

      InputPayload:
        InstanceId: '{{InstanceId}}'
        AlarmsMetadata: '{{appendDiskAlarmsConfigs.AlarmsMetadata}}'
        Environment: '${environment}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
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
