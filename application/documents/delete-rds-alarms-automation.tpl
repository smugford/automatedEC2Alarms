description: Delete Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  DBInstanceIdentifier:
    type: String
    description: (Required) The DB Instance Identifier
mainSteps:
  - name: DeleteDocumentStack
    action: 'aws:deleteStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{DBInstanceIdentifier}}-alarms-stack'
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
               Message='Failed. The alarm can not be deleted for RDS ' + DBInstanceIdentifier + ' in account ' + account_id,
            )
      InputPayload:
        DBInstanceIdentifier: '{{DBInstanceIdentifier}}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true
