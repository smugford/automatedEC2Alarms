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
  - name: updateOrDeleteCompositeCapacityAlarm
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
            host_id = events['HostId']
            environment = events['Environment']
            alarms = cw.describe_alarms(
                AlarmNamePrefix=f"{environment}-{host_id}"
            )
            host_alarm_stacks = []
            for alarm in alarms['MetricAlarms']:
                host_alarm_stacks.append(alarm['AlarmName'])
                alarm_metadata, instance_type, instance_type_alarm = get_composite_alarm_from_metric_alarm(alarm, cw)
                update_composite_alarm_in_place(alarm_metadata, cw, instance_type, instance_type_alarm)
            return host_alarm_stacks


        def get_composite_alarm_from_metric_alarm(alarm, cw):
            alarm_metadata = alarm.split("-")
            instance_type = alarm_metadata[2]
            instance_type_alarm = cw.describe_alarms(
                AlarmNames=[f"{instance_type}-Available-Capacity"],
                AlarmTypes=['CompositeAlarm']
            )
            return alarm_metadata, instance_type, instance_type_alarm


        def update_composite_alarm_in_place(alarm_metadata, cw, instance_type, instance_type_alarm):
            alarm_config = instance_type_alarm['CompositeAlarms'][0]

            instance_type_alarm = get_all_alarms_for_one_instance_type(alarm_metadata, cw, instance_type)
            if instance_type_alarm:
                alarm_config['AlarmRule'] = " AND ".join(instance_type_alarm)
                cw.put_composite_alarm(
                    ActionsEnabled=alarm_config['ActionsEnabled'],
                    AlarmActions=[alarm_config['AlarmActions']],
                    AlarmDescription=alarm_config['AlarmDescription'],
                    AlarmName=alarm_config['AlarmName'],
                    AlarmRule=alarm_config['AlarmRule'],
                    InsufficientDataActions=[alarm_config['InsufficientDataActions']],
                    OKActions=[alarm_config['OKActions']]
                )
            else:
                cw.delete_alarms(
                    AlarmNames=[
                        alarm_config['AlarmName']
                    ]
                )


        def get_all_alarms_for_one_instance_type(alarm_metadata, cw, instance_type):
            environment = alarm_metadata[0]
            host_id = alarm_metadata[1]
            dedicated_host_alarms = cw.describe_alarms(
                AlarmNames=[compose_possible_alarm_names_for_instance_type(environment, instance_type, host_id)]
            )
            dedicated_host_alarm_names = extract_alarm_names_from_dedicated_host_alarms(dedicated_host_alarms)
            return dedicated_host_alarm_names


        def compose_possible_alarm_names_for_instance_type(environment, instance_type, host_id):
            composed_alarms_names = []
            for dedicated_host in get_dedicated_hosts_ids():
                if dedicated_host == host_id:
                    continue
                composed_alarms_names.append(f"{environment}-{dedicated_host}-{instance_type}-Capacity-Alarm")
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
        HostId: '{{HostId}}'
        Environment: '${environment}'
    outputs:
      - Name: HostAlarms
        Selector: '$.Payload.HostAlarms'
        Type: StringList
  - name: DeleteAlarmsStack
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from boto3 import client


        def script_handler(events, context):
            alarms_names = events['HostAlarms']
            cf = client('cloudformation')
            for alarm_name in alarms_names:
                cf.delete_stack(
                    StackName=extract_stack_name_from_alarm(alarm_name)
                )


        def extract_stack_name_from_alarm(alarm_name):
            alarm_metadata = alarm_name.split("-")
            host_id = alarm_metadata[1]
            instance_type = alarm_metadata[2]
            return f"{host_id}-{instance_type}-alarms-stack"

      InputPayload:
        HostAlarms: '{{updateOrDeleteCompositeCapacityAlarm.HostAlarms}}'
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
            host_id = events['HostId']
            sns_topic_low = events['sns_topic_low']
            response = sns.publish(
               TopicArn=sns_topic_low,
               Message='Failed. The alarm can not be created for host ' + host_id + ' in account ' + account_id,
            )
      InputPayload:
        HostId: '{{ HostId }}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true
