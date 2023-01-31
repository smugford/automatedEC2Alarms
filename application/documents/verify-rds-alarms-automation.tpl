description: Verify Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  DBInstanceIdentifier:
    type: String
    description: (Optional) The DB Instance Identifier
    default: ''
mainSteps:
  - name: getEngine
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        from typing import Dict

        from boto3 import client


        def script_handler(events, context):
            if db_id_is_passed(events):
                return get_platform_of_one_instance(events)
            else:
                return get_platform_of_all_instances()


        def db_id_is_passed(events):
            return 'DBInstanceIdentifier' in events and events['DBInstanceIdentifier']


        def get_platform_of_one_instance(events):
            rds = client('rds')
            alarms_metadata: Dict[str, Dict[str, str]] = {}
            db_identifier = events['DBInstanceIdentifier']
            instance = rds.describe_db_instances(
                DBInstanceIdentifier=db_identifier
            )['DBInstances'][0]
            store_instance_platform_to_alarms_metadata(alarms_metadata, instance)
            return alarms_metadata


        def get_platform_of_all_instances():
            rds = client('rds')
            alarms_metadata: Dict[str, Dict[str, str]] = {}
            paginator = rds.get_paginator('describe_db_instances')
            instances = paginator.paginate().build_full_result()
            for instance in instances['DBInstances']:
                store_instance_platform_to_alarms_metadata(alarms_metadata, instance)
            return alarms_metadata


        def store_instance_platform_to_alarms_metadata(alarms_metadata, instance):
            alarms_metadata.setdefault(instance['DBInstanceIdentifier'], {'Platform': get_instance_engine(instance)})


        def get_instance_engine(instance):
            return instance['Engine'] if 'Engine' in instance else ''

      InputPayload:
        DBInstanceIdentifier: '{{DBInstanceIdentifier}}'
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

        rds = client('rds')


        def script_handler(events, context):
            if db_id_is_passed(events):
                return get_after_hours_tag_of_one_instance(events, context)
            else:
                return get_after_hours_tag_of_all_instances(events, context)


        def db_id_is_passed(events):
            return 'DBInstanceIdentifier' in events and events['DBInstanceIdentifier']


        def get_after_hours_tag_of_one_instance(events, context):
            alarms_metadata = events['AlarmsMetadata']
            db_id = events['DBInstanceIdentifier']
            store_after_hours_tag_for_db(alarms_metadata, context, db_id)
            return alarms_metadata


        def get_after_hours_tag_of_all_instances(events, context):
            alarms_metadata = events['AlarmsMetadata']
            for db in alarms_metadata:
                store_after_hours_tag_for_db(alarms_metadata, context, db)
            return alarms_metadata


        def store_after_hours_tag_for_db(alarms_metadata, context, db_id):
            after_hours = extract_after_hours_tag(get_all_rds_tags(compose_rds_arn(db_id, context)))
            alarms_metadata[db_id]['after-hours-support'] = after_hours
            return after_hours


        def extract_after_hours_tag(tag_list):
            after_hours = "NoTagAvailable"
            for i in tag_list:
                if i['Key'] == 'after-hours-support':
                    after_hours = i['Value']
            return after_hours


        def get_all_rds_tags(db_arn):
            return rds.list_tags_for_resource(
                ResourceName=db_arn)['TagList']


        def compose_rds_arn(db_id, context):
            return f"arn:aws:rds:us-east-1:{context.get('global:ACCOUNT_ID')}:db:{db_id}"

      InputPayload:
        DBInstanceIdentifier: '{{DBInstanceIdentifier}}'
        AlarmsMetadata: '{{getEngine.AlarmsMetadata}}'
    outputs:
      - Name: AlarmsMetadata
        Selector: '$.Payload'
        Type: StringMap
  - name: composeExpectedAlarms
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        def script_handler(events, context):
            if db_id_is_passed(events):
                return compose_rds_alarms_for_one_instance(events, context)
            else:
                return compose_rds_alarms_for_all_instances(events, context)


        def db_id_is_passed(events):
            return 'DBInstanceIdentifier' in events and events['DBInstanceIdentifier']


        def compose_rds_alarms_for_one_instance(events, context):
            db_id = events['DBInstanceIdentifier']
            alarms_metadata = events['AlarmsMetadata']
            store_alarms_configs(alarms_metadata, context, events, db_id)
            return alarms_metadata


        def compose_rds_alarms_for_all_instances(events, context):
            alarms_metadata = events['AlarmsMetadata']
            for db in alarms_metadata:
                store_alarms_configs(alarms_metadata, context, events, db)
            return alarms_metadata


        def store_alarms_configs(alarms_metadata, context, events, db):
            alarm_configs = [
                {
                    'AlarmName': f"{events['Environment']}-{db}-CPUUtilization-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "RDS CPUUtilization Alarm",
                        "alarm_name": "CPUUtilization-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "RDS",
                        "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/RDS',
                    'MetricName': 'CPUUtilization',
                    'Statistic': 'Average',
                    'Period': '300',
                    'EvaluationPeriods': '5',
                    'Threshold': '90.0',
                    'ComparisonOperator': 'GreaterThanThreshold',
                    'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{db}-FreeableMemory-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "RDS Freeable Memory Alarm",
                        "alarm_name": "FreeableMemory-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "RDS",
                        "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/RDS',
                    'MetricName': 'FreeableMemory',
                    'Statistic': 'Average',
                    'Period': '600',
                    'EvaluationPeriods': '2',
                    'ComparisonOperator': 'LessThanOrEqualToThreshold',
                    'Threshold': '1000000000.0',
                    'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{db}-DatabaseConnections-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "RDS Database Connections Alarm",
                        "alarm_name": "DatabaseConnections-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "RDS",
                        "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/RDS',
                    'MetricName': 'DatabaseConnections',
                    'Statistic': 'Average',
                    'Period': '300',
                    'EvaluationPeriods': '5',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Threshold': '100.0',
                    'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{db}-DiskQueueDepth-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "RDS Disk Queue Depth Alarm",
                        "alarm_name": "DiskQueueDepth-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "RDS",
                        "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/RDS',
                    'MetricName': 'DiskQueueDepth',
                    'Statistic': 'Average',
                    'Period': '3600',
                    'EvaluationPeriods': '4',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Threshold': '3000.0',
                    'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{db}-ReadLatency-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "RDS Read Latency Alarm",
                        "alarm_name": "ReadLatency-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "RDS",
                        "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/RDS',
                    'MetricName': 'ReadLatency',
                    'Statistic': 'Average',
                    'Period': '3600',
                    'EvaluationPeriods': '4',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Threshold': '3000.0',
                    'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                    'TreatMissingData': 'breaching'
                },
                {
                    'AlarmName': f"{events['Environment']}-{db}-WriteLatency-Alarm",
                    'ActionsEnabled': True,
                    'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                    'OKActions': [f"{events['AlarmSnsTopic']}"],
                    'AlarmDescription': {
                        "region": f"{context.get('global:REGION')}",
                        "description": "RDS Write Latency Alarm",
                        "alarm_name": "WriteLatency-Alarm",
                        "environment": f"{events['Environment']}",
                        "account_id": f"{context.get('global:ACCOUNT_ID')}",
                        "type": "RDS",
                        "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                    },
                    'Namespace': 'AWS/RDS',
                    'MetricName': 'WriteLatency',
                    'Statistic': 'Average',
                    'Period': '3600',
                    'EvaluationPeriods': '4',
                    'ComparisonOperator': 'GreaterThanOrEqualToThreshold',
                    'Threshold': '3000.0',
                    'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                    'TreatMissingData': 'breaching'
                }
            ]
            if 'aurora' in str(alarms_metadata[db]['Platform']).lower():
                alarm_configs.append(
                    {
                        'AlarmName': f"{events['Environment']}-{db}-FreeLocalStorage-Alarm",
                        'ActionsEnabled': True,
                        'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                        'OKActions': [f"{events['AlarmSnsTopic']}"],
                        'AlarmDescription': {
                            "region": f"{context.get('global:REGION')}",
                            "description": "RDS Free Local Storage Alarm",
                            "alarm_name": "FreeLocalStorage-Alarm",
                            "environment": f"{events['Environment']}",
                            "account_id": f"{context.get('global:ACCOUNT_ID')}",
                            "type": "RDS",
                            "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                        },
                        'Namespace': 'AWS/RDS',
                        'MetricName': 'FreeLocalStorage',
                        'Statistic': 'Average',
                        'Period': '300',
                        'EvaluationPeriods': '2',
                        'Threshold': '5000000000.0',
                        'ComparisonOperator': 'LessThanOrEqualToThreshold',
                        'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                        'TreatMissingData': 'breaching'
                    }
                )
            else:
                alarm_configs.append(
                    {
                        'AlarmName': f"{events['Environment']}-{db}-FreeStorageSpace-Alarm",
                        'ActionsEnabled': True,
                        'AlarmActions': [f"{events['AlarmSnsTopic']}"],
                        'OKActions': [f"{events['AlarmSnsTopic']}"],
                        'AlarmDescription': {
                            "region": f"{context.get('global:REGION')}",
                            "description": "RDS Free Storage Space Alarm",
                            "alarm_name": "FreeStorageSpace-Alarm",
                            "environment": f"{events['Environment']}",
                            "account_id": f"{context.get('global:ACCOUNT_ID')}",
                            "type": "RDS",
                            "after-hours-support": f"{alarms_metadata[db]['after-hours-support']}"
                        },
                        'Namespace': 'AWS/RDS',
                        'MetricName': 'FreeStorageSpace',
                        'Statistic': 'Average',
                        'Period': '300',
                        'EvaluationPeriods': '2',
                        'Threshold': '5000000000.0',
                        'ComparisonOperator': 'LessThanOrEqualToThreshold',
                        'Dimensions': [{'Name': 'DBInstanceIdentifier', 'Value': f'{db}'}],
                        'TreatMissingData': 'breaching'
                    }
                )
            alarms_metadata[db]['AlarmConfigs'] = alarm_configs

      InputPayload:
        DBInstanceIdentifier: '{{DBInstanceIdentifier}}'
        AlarmsMetadata: '{{getAfterHourTag.AlarmsMetadata}}'
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
            if db_id_is_passed(events):
                return verify_alarms_for_one_instance(events)
            else:
                return verify_alarms_for_all_instances(events, context)


        def db_id_is_passed(events):
            return 'DBInstanceIdentifier' in events and events['DBInstanceIdentifier']


        def verify_alarms_for_one_instance(events):
            cw = client('cloudwatch')
            db = events['DBInstanceIdentifier']
            verifier_output = verify_one_instance(cw, events, db)
            return {"BAM Verifier Output": verifier_output}


        def verify_alarms_for_all_instances(events, context):
            cw = client('cloudwatch')
            alarms_metadata = events['AlarmsMetadata']
            verifier_output = {}
            for db in alarms_metadata:
                verifier_output[db] = verify_one_instance(cw,events,db)
            return {"BAM Verifier Output": verifier_output}


        def verify_one_instance(cw, events, db):
            actual_instance_alarms = get_all_alarms_for_db(cw, db, events)
            expected_instance_alarms = events['AlarmsMetadata'][db]['AlarmConfigs']
            verifier_output = ""
            for expected_alarm in expected_instance_alarms:
                actual_alarm = get_alarm(expected_alarm, actual_instance_alarms)
                if actual_alarm:
                    verifier_output += compare_alarm_configs(expected_alarm, actual_alarm, expected_alarm["AlarmName"])
                else:
                    verifier_output += f"Missing: {expected_alarm['AlarmName']}\n"
            return verifier_output


        def get_all_alarms_for_db(cw, db, events):
            list_response = cw.describe_alarms(
                AlarmNamePrefix=f"{events['Environment']}-{db}",
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
        DBInstanceIdentifier: '{{DBInstanceIdentifier}}'
        AlarmsMetadata: '{{composeExpectedAlarms.AlarmsMetadata}}'
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
            dbInstanceIdentifier = events['DBInstanceIdentifier']
            sns_topic_low = events['sns_topic_low']
            response = sns.publish(
               TopicArn=sns_topic_low,
               Message='Failed. The alarm can not be created for instance ' + dbInstanceIdentifier + ' in account ' + account_id,
            )
      InputPayload:
        DBInstanceIdentifier: '{{ DBInstanceIdentifier }}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true
