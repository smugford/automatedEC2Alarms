description: Delete ELB/TG listener
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  ruleArn:
    type: String
    description: (Required) Name of the application or network load balancer
mainSteps:
  - name: updateELBRules
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import re
        from os import environ
        import boto3

        targetGroups = []
        targetGroupsDimension = {}
        alarm_namespace = ''
        ruleArn = ''
        loadBalancerArn = ''
        loadBalancerName = ''
        loardBalancerDimension = ''
        cw = boto3.client('cloudwatch')
        elb = boto3.client("elbv2")


        def get_loadbalancer_target_groups(loadBalancerArn):
            targetGrpDimension = {}
            targetGrps = []
            targetgroups = elb.describe_target_groups(LoadBalancerArn=loadBalancerArn)
            for targetroup in targetgroups['TargetGroups']:
                targetgrp = targetroup['TargetGroupName']
                targetGrps.append(targetgrp)
                targetName = (targetroup['TargetGroupArn'].split(":"))[-1]
                targetGrpDimension[targetgrp] = targetName
            return targetGrps, targetGrpDimension


        def check_elb_alarms(loadBalancerName, targetGroups, loardBalancerDimension, targetDimension, alarmNameSpace, sns_topic_high, Environment, Aws_Region, AccountId):
            paginator = cw.get_paginator('describe_alarms')
            alarms_response = paginator.paginate(AlarmNamePrefix=loadBalancerName).build_full_result()
            for targetGroup in targetGroups:

                alarm_exist = False
                for alarm in alarms_response['MetricAlarms']:
                    if loadBalancerName + '-' + targetGroup in alarm['AlarmName']:
                        alarm_exist = True
                        continue
                    elif loadBalancerName in alarm['AlarmName']:
                        if ('-HealthyHostCount' in alarm['AlarmName']) or ('-UnHealthyHostCount' in alarm['AlarmName']):
                            targetGroupName = (re.split('-HealthyHostCount|-UnHealthyHostCount', alarm['AlarmName'])[0]).split(loadBalancerName+'-')[1]
                            if targetGroupName not in targetGroups:
                                cw.delete_alarms(AlarmNames=[alarm['AlarmName']])
                if not alarm_exist:
                    tgdimension = targetDimension[targetGroup]
                    create_alarms(loadBalancerName, targetGroup, loardBalancerDimension, tgdimension, alarmNameSpace, sns_topic_high, Environment, Aws_Region, AccountId)


        def create_alarms(loadbalancer, targetgroup, loardBalancerDimension, tgdimension, alarm_namespace, sns_topic_high, Environment, Aws_Region, AccountId):
            cw.put_metric_alarm(
                AlarmName=loadbalancer + '-' + targetgroup + '-UnHealthyHostCount',
                ComparisonOperator='GreaterThanOrEqualToThreshold',
                EvaluationPeriods=2,
                MetricName='UnHealthyHostCount',
                Namespace=alarm_namespace,
                Period=60,
                Statistic='Average',
                Threshold=1,
                ActionsEnabled=True,
                TreatMissingData='breaching',
                AlarmDescription="""{\"region\":\"%s\",\"description\":\"ELB UnHealthy Host Count\"
                                    ,\"environment\":\"%s\",\"account_id\":\"%s\"
                                    ,\"TargetGroup\":\"%s\",\"LoadBalancer\":\"%s\"}""" \
                                    % (Aws_Region, Environment, AccountId, targetgroup, loadBalancerName),
                Dimensions=[
                    {
                        'Name': 'LoadBalancer',
                        'Value': loardBalancerDimension
                    },
                    {
                        'Name': 'TargetGroup',
                        'Value': tgdimension
                    }
                ]
            )
            cw.put_metric_alarm(
                AlarmName=loadbalancer+'-'+targetgroup+'-HealthyHostCount',
                ComparisonOperator='LessThanThreshold',
                EvaluationPeriods=2,
                MetricName='HealthyHostCount',
                Namespace=alarm_namespace,
                Period=60,
                Statistic='Average',
                Threshold=1,
                ActionsEnabled=True,
                TreatMissingData='breaching',
                AlarmDescription="""{\"region\":\"%s\",\"description\":\"ELB Healthy Host Count\"
                                    ,\"environment\":\"%s\",\"account_id\":\"%s\"
                                    ,\"TargetGroup\":\"%s\",\"LoadBalancer\":\"%s\"}""" \
                                    % (Aws_Region, Environment, AccountId, targetgroup, loadBalancerName),
                Dimensions=[
                    {
                        'Name': 'LoadBalancer',
                        'Value': loardBalancerDimension
                    },
                    {
                        'Name': 'TargetGroup',
                        'Value': tgdimension
                    },
                ]
            )


        def script_handler(events, context):
            ruleArn = events['ruleArn']
            sns_topic_high = events['sns_topic_high']
            Environment = events['Environment']
            Aws_Region = events['Aws_Region']
            AccountId = sns_topic_high.split(':')[4]
            alarm_namespace = 'AWS/ApplicationELB'
            loadBalancerName = ruleArn.split("/")[2]
            response = elb.describe_load_balancers(Names=[loadBalancerName])
            loadBalancerArn = response['LoadBalancers'][0]['LoadBalancerArn']
            loardBalancerDimension = (loadBalancerArn.split(":loadbalancer/"))[-1]
            targetGroups, targetGroupsDimension = get_loadbalancer_target_groups(loadBalancerArn)
            check_elb_alarms(loadBalancerName, targetGroups, loardBalancerDimension, targetGroupsDimension, alarm_namespace, sns_topic_high, Environment, Aws_Region, AccountId)

            return {loadBalancerName : loadBalancerName}
      InputPayload:
        ruleArn: '{{ ruleArn }}'
        sns_topic_high: '${sns_topic_high}'
        Environment: '${environment}'
        Aws_Region: '${aws_region}'
    outputs:
      - Name: loadBalancerName
        Selector: $.Payload.loadBalancerName
        Type: String
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
            elbname = events['elbname']
            sns_topic_high = events['sns_topic_high']
            response = sns.publish(
                TopicArn=sns_topic_high,
                Message='Failed. The alarm can not be created for ELB/CLB ' + elbname + ' in account ' + account_id,
            )
      InputPayload:
        elbname: '{{ updateELBRules.loadBalancerName }}'
        sns_topic_high: '${sns_topic_high}'
    isEnd: true
