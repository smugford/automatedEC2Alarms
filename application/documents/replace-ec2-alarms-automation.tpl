description: Create Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  InstanceId:
    type: String
    description: (Required) The ID of the instance
mainSteps:
  - name: deleteAlarms
    action: aws:executeAutomation
    onFailure: 'step:onFailure'
    inputs:
      DocumentName: '${company}-${environment}-delete-ec2-alarms-automation'
      RuntimeParameters:
        InstanceId: 
        - '{{ InstanceId }}'
  - name: createAlarms
    action: aws:executeAutomation
    onFailure: 'step:onFailure'
    inputs:
      DocumentName: '${company}-${environment}-create-ec2-alarms-automation'
      RuntimeParameters:
        InstanceId: 
        - '{{ InstanceId }}'
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
