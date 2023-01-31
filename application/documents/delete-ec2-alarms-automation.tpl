description: Delete Alarms Stack
schemaVersion: '0.3'
assumeRole: ${assume_role_arn}
parameters:
  InstanceId:
    type: String
    description: (Required) The ID of the instance
mainSteps:
  - action: 'aws:deleteStack'
    onFailure: 'step:onFailure'
    inputs:
      StackName: '{{InstanceId}}-alarms-stack'
    name: DeleteDocumentStack
  - name: deleteLinuxDiskAlarms
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3

        cloudwatch = boto3.client('cloudwatch')

        def get_metrics(InstanceId):
            response = cloudwatch.list_metrics(
                Namespace='CWAgent',
                MetricName='disk_used_percent',
                Dimensions=[
                    {
                        'Name': 'InstanceId',
                        'Value': InstanceId
                    }
                ]
            )
            devices = []
            for i in range(0, len(response['Metrics'])):
                for b in range(0, len(response['Metrics'][i]['Dimensions'])):
                    if 'device' in response['Metrics'][i]['Dimensions'][b]['Name']:
                        devices.append(response['Metrics'][i]['Dimensions'][b]['Value'])
            sorted = list(dict.fromkeys(devices))
            return sorted

       
        def delete_alarms(InstanceId, sortedDevices, Environment):

            for device in sortedDevices:
                cloudwatch.delete_alarms(
                    AlarmNames=[
                        Environment + '-' + InstanceId + '-LinuxDiskFreeSpace-' + device
                    ]
                )

        def script_handler(events, context):
           InstanceId = events['InstanceId']
           Environment = events['Environment']
           sortedDevices = get_metrics(InstanceId) 
           delete_alarms(InstanceId, sortedDevices, Environment)
          
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        Environment: '${environment}'
  - name: deleteWindowsDiskAlarms
    action: 'aws:executeScript'
    onFailure: 'step:onFailure'
    inputs:
      Runtime: python3.7
      Handler: script_handler
      Script: |-
        import boto3

        cloudwatch = boto3.client('cloudwatch')

        def get_metrics(InstanceId):
          response = cloudwatch.list_metrics(
              Namespace='CWAgent',
              MetricName='LogicalDisk % Free Space',
              Dimensions=[
                  {
                      'Name': 'InstanceId',
                      'Value': InstanceId
                  }
              ]
          )
          disk = []
          for i in range(0, len(response['Metrics'])):
                for b in range(0, len(response['Metrics'][i]['Dimensions'])):
                    if 'instance' in response['Metrics'][i]['Dimensions'][b]['Name']:
                        disk.append(response['Metrics'][i]['Dimensions'][b]['Value'])
          sortedDisks = list(dict.fromkeys(disk))
          print(sortedDisks)
          return sortedDisks 
       
        def delete_alarms(InstanceId, sortedDisks, Environment):

            for sortedDisk in sortedDisks:
                cloudwatch.delete_alarms(
                    AlarmNames=[
                        Environment + '-' + InstanceId + '-WindowsDiskFreeSpace-' + sortedDisk
                    ]
                )

        def script_handler(events, context):
           InstanceId = events['InstanceId']
           Environment = events['Environment']
           sortedDisks = get_metrics(InstanceId)
           delete_alarms(InstanceId, sortedDisks, Environment)
          
      InputPayload:
        InstanceId: '{{ InstanceId }}' 
        Environment: '${environment}'
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
               Message='Failed. The alarm can not be deleted for instance ' + InstanceId + ' in account ' + account_id,
            )
      InputPayload:
        InstanceId: '{{ InstanceId }}'
        sns_topic_low: '${sns_topic_low}'
    isEnd: true

