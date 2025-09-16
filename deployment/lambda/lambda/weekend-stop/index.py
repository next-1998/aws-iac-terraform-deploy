import boto3
from datetime import datetime

region = 'ap-northeast-2'


def lambda_handler(event, context):
    rds = boto3.client('rds', region_name=region)
    ec2 = boto3.client('ec2', region_name=region)
    ec2_tags = ec2.describe_tags(
        Filters=[
            {
                'Name': 'resource-type',
                'Values': ['instance']
            }
        ]
    )

    weekend_stop_enable = False
    for tag in ec2_tags['Tags']:
        if tag['Key'] == "WEEKEND_STOP_ENABLE" and tag['Value'].lower() == "true":
            weekend_stop_enable = True
            print('[weekend-stop] Now: ' + datetime.today().strftime("%Y/%m/%d %H:%M:%S"))
            break

    if weekend_stop_enable:
        # ec2
        for tag in ec2_tags['Tags']:
            if tag['Key'] == "Name" and \
                    (tag['Value'].endswith('-web-ide')
                     or tag['Value'].endswith('-ASG-EC2')
                     or tag['Value'].endswith('-was')
                     or tag['Value'].endswith('eks-eks-mixed-eks_asg')):
                instance = tag['ResourceId']
                try:
                    if event['action'] == "start":
                        ec2.start_instances(InstanceIds=[instance])
                        print('[weekend-stop] Starting instance:' + instance)
                    elif event['action'] == "stop":
                        ec2.stop_instances(InstanceIds=[instance])
                        print('[weekend-stop] Stopping instance:' + instance)
                except Exception as ex:
                    print(ex)

        # rds
        try:
            if event['db_instance_id']:
                if event['action'] == "start":
                    rds.start_db_instance(DBInstanceIdentifier=event['db_instance_id'])
                    print('[weekend-stop] Starting RDS Instance: ' + str(event['db_instance_id']))
                elif event['action'] == "stop":
                    rds.stop_db_instance(DBInstanceIdentifier=event['db_instance_id'])
                    print('[weekend-stop] Stopping RDS Instance: ' + str(event['db_instance_id']))
        except Exception as ex:
            print(ex)
