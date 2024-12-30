import secrets
import os
import time
import random
import concurrent.futures
import boto3
import botocore
import ddtrace
from botocore.config import Config
from locust import User, TaskSet, task, between, events
from ddtrace.propagation.http import HTTPPropagator
import requests

class TimeoutException(Exception):
    pass

ddtrace.patch(botocore=True)
ddtrace.config.botocore['distributed_tracing'] = False

client_config = Config(
    connect_timeout = 10,
    read_timeout = 30,
    retries = {
        'total_max_attempts': 1,
        'mode': 'standard'
    }
)

aws_regions = [
    # "us-east-1",
    # "us-east-2",
    # "eu-west-1",
    # "eu-west-2",
    # "ap-east-1",
    # "ap-south-1",
    # "ap-southeast-1",
    "ap-southeast-2",
    # "ap-southeast-4",
    # "ap-northeast-1"
]

allowed_errors = [
    'AccessDenied',
    'AccessDeniedException',
    'UnauthorizedOperation',
    'InvalidClientTokenId',
    'UnrecognizedClientException',
    'AuthFailure',

    'AWS.SimpleQueueService.NonExistentQueue',

    'Throttling',
    'ThrottlingException',
    'ThrottledException',
    'RequestThrottledException',
    'TooManyRequestsException',
    'ProvisionedThroughputExceededException',
    'TransactionInProgressException',
    'RequestLimitExceeded',
    'BandwidthLimitExceeded',
    'LimitExceededException',
    'RequestThrottled',
    'SlowDown',
    'EC2ThrottledException',

    'KMS.NotFoundException',
]

cloudfront_dist_config = {
    "CallerReference": "cf-cli-distribution",
    "Comment": "Test Cloudfront Distribution",
    "Origins": {
        "Quantity": 1,
        "Items": [{
            "Id": "test-cloudfront",
            "DomainName": "test-cloudfront.s3.amazonaws.com",
            "S3OriginConfig": {
                "OriginAccessIdentity": ""
            }
        }]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "test-cloudfront",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Quantity": 0,
            "Enabled": False
        },
        "ForwardedValues": {
            "Cookies": {"Forward": "all"},
            "Headers": {"Quantity": 0},
            "QueryString": False,
            "QueryStringCacheKeys": {"Quantity": 0}
        },
        "DefaultTTL": 86400,
        "MinTTL": 3600
    },
    "Enabled": True
}

custom_responses = {
    "CustomResponseTasks": {
        "aws_xray_create_group_customresponse_block": '"aws_xray_create_group"',
        "aws_xray_delete_group_customresponse_block": '"aws_xray_delete_group"',
        "aws_xray_update_group_customresponse_block": '"aws_xray_update_group"',
        "aws_xray_get_group_customresponse_block": '"aws_xray_get_group"',
    }
}

boto3.setup_default_session(region_name='ap-southeast-2')

USER_WAIT_MIN = int(os.getenv('USER_WAIT_MIN', 4))
USER_WAIT_MAX = int(os.getenv('USER_WAIT_MAX', 6))
MAX_CLIENT_REUSE = int(os.getenv('MAX_CLIENT_REUSE', 10))
DEFAULT_TEST_TIMEOUT = int(os.getenv('DEFAULT_TEST_TIMEOUT', 60))

def add_trace_headers(request, **kwargs):
    span = ddtrace.tracer.current_span()
    span.service = "locust"
    headers = {}
    HTTPPropagator.inject(span.context, headers)
    for h, v in headers.items():
        request.headers.add_header(h, v)

all_clients = {}

def get_client(service, region=""):
    if region == "":
        region = secrets.choice(aws_regions)

    c = all_clients.get(service, {}).get(region)
    if c and c['count'] > 0:
        all_clients[service][region]['count'] -= 1
        return c['client']

    client = boto3.client(service, region_name=region, config=client_config)
    client.meta.events.register_first('before-sign.*.*', add_trace_headers)

    if service not in all_clients:
        all_clients[service] = {}

    all_clients[service][region] = {
        'client': client,
        'count': random.randrange(MAX_CLIENT_REUSE)
    }
    return client

def result_decorator(method):
    def decorator(self):
        class_name = self.__class__.__name__
        method_name = method.__name__
        method_parts = method_name.split('_')

        idx = -1
        if method_parts[idx].isnumeric():
            idx = -2

        validity = method_parts[idx]

        custom_resp = False
        if method_parts[idx-1] == "customresponse":
            custom_resp = True

        if validity == 'allow':
            should_block = False
        elif validity == 'block':
            should_block = True
        else:
            return failure(class_name, method_name, time.time(), Exception("invalid_test: method name must end with '_block' or '_allow'"))

        if custom_resp and not should_block:
            return failure(class_name, method_name, time.time(), Exception("invalid_test: customresponse test must also block"))

        start_time = time.time()
        try:
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(method, self)
                future.result(timeout=DEFAULT_TEST_TIMEOUT)

        except concurrent.futures.TimeoutError as e:
            raise TimeoutException(f"Timeout ({DEFAULT_TEST_TIMEOUT}s) exceeded") from e

        except botocore.exceptions.ClientError as error:
            # If error code is allowed, treat as a successful request
            if not should_block and error.response['Error']['Code'] in allowed_errors:
                return success(class_name, method_name, start_time)
            # otherwise check for Kivera error
            return check_err_message(should_block, custom_resp, class_name, method_name, start_time, error)

        except Exception as error:
            # check for Kivera error
            return check_err_message(should_block, custom_resp, class_name, method_name, start_time, error)

        # on successful request
        if should_block:
            return failure(class_name, method_name, start_time, Exception("API call should have been blocked by Kivera"))

        return success(class_name, method_name, start_time)

    return decorator


def check_err_message(should_block, custom_resp, class_name, method_name, start_time, error):

    if not should_block:
        return failure(class_name, method_name, start_time, error)

    if "Kivera.Error" not in str(error) and "Oops, your request has been blocked." not in str(error):
        return failure(class_name, method_name, start_time, Exception("Request Not Blocked: " + str(error)))

    if custom_resp:
        expected = custom_responses[class_name][method_name]
        if not contains_custom_response(error, expected):
            return failure(class_name, method_name, start_time, Exception(f"Missing Custom Response: '{expected}': {str(error)}"))

    return success(class_name, method_name, start_time)


def contains_custom_response(error, expected):
    parts = str(error).split("Errors: ")
    if len(parts) != 2:
        return False
    for resp in parts[1].strip().lstrip("[").rstrip("]").split(","):
        if resp == expected:
            return True
    return False


def success(class_name, method_name, s):
    t = int((time.time() - s) * 1000)
    events.request.fire(
        request_type=class_name,
        name=method_name,
        response_time=t,
        response_length=0)

def failure(class_name, method_name, s, e):
    t = int((time.time() - s) * 1000)
    events.request.fire(
        request_type=class_name,
        name=method_name,
        response_time=t,
        exception=e,
        response_length=0)


### EC2 ###
class AwsEc2Tasks(TaskSet):
    @task(3)
    @result_decorator
    def aws_ec2_describe_instances_block(self):
        client = get_client('ec2')
        client.describe_instances()

    @task(1)
    @result_decorator
    def aws_ec2_describe_instances_allow(self):
        client = get_client('ec2')
        client.get_paginator('describe_instances').paginate(PaginationConfig={'MaxItems': 1})


    @task(3)
    @result_decorator
    def aws_ec2_authorize_security_group_ingress_block(self):
        client = get_client('ec2')
        client.authorize_security_group_ingress(
            CidrIp='0.0.0.0/0',
            ToPort=22,
            FromPort=22,
            IpProtocol="TCP",
            GroupId="sg-09a320fc24c2fd3c5",
        )

    @task(2)
    @result_decorator
    def aws_ec2_create_key_pair_block(self):
        client = get_client('ec2')
        client.create_key_pair(KeyName='test-key-pair', KeyType='rsa', KeyFormat='pem' )

    @task(2)
    @result_decorator
    def aws_ec2_create_key_pair_allow(self):
        client = get_client('ec2')
        client.create_key_pair(KeyName='test-key-pair', KeyType='ed25519', KeyFormat='pem' )

    @task(2)
    @result_decorator
    def aws_ec2_create_volume_block(self):
        client = get_client('ec2', 'ap-southeast-2')
        client.create_volume(AvailabilityZone="ap-southeast-2a", Encrypted=False)

    @task(1)
    @result_decorator
    def aws_ec2_create_volume_allow(self):
        client = get_client('ec2', 'ap-southeast-2')
        client.create_volume(AvailabilityZone="ap-southeast-2a", Encrypted=True, KmsKeyId='alias/secure-key', Size=100)



### DYNAMODB ###
class AwsDynamoDBTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_dynamodb_list_tables_allow(self):
        client = get_client('dynamodb')
        client.list_tables()

    @task(3)
    @result_decorator
    def aws_dynamodb_create_table_block(self):
        client = get_client('dynamodb')
        client.create_table(
            TableName='user-table',
            AttributeDefinitions=[{
                'AttributeName': 'UserId',
                'AttributeType': 'S'
            }],
            KeySchema=[{
                'AttributeName': 'UserId',
                'KeyType': 'HASH'
            }],
            BillingMode='PAY_PER_REQUEST',
            SSESpecification={
                'Enabled': True,
                'SSEType': 'KMS',
                'KMSMasterKeyId': 'alias/aws/dynamodb'
            },
            TableClass='STANDARD'
        )

    @task(3)
    @result_decorator
    def aws_dynamodb_create_table_allow(self):
        client = get_client('dynamodb')
        client.create_table(
            TableName='user-table',
            AttributeDefinitions=[{
                'AttributeName': 'UserId',
                'AttributeType': 'S'
            }],
            KeySchema=[{
                'AttributeName': 'UserId',
                'KeyType': 'HASH'
            }],
            BillingMode='PAY_PER_REQUEST',
            SSESpecification={
                'Enabled': True,
                'SSEType': 'KMS',
                'KMSMasterKeyId': 'alias/secure-key'
            },
            TableClass='STANDARD'
        )



### STS ###
class AwsStsTasks(TaskSet):
    @task(4)
    @result_decorator
    def aws_sts_get_caller_identity_allow(self):
        client = get_client('sts')
        client.get_caller_identity()

    @task(2)
    @result_decorator
    def aws_sts_assume_role_block_1(self):
        client = get_client('sts')
        client.assume_role(
            RoleArn="arn:aws:iam::326190351503:role/test-role",
            RoleSessionName="invalid-session-name",
        )

    @task(2)
    @result_decorator
    def aws_sts_assume_role_block_2(self):
        client = get_client('sts')
        client.assume_role(
            RoleArn="arn:aws:iam::000000000000:role/test-role",
            RoleSessionName="org-dev-session",
        )

    @task(4)
    @result_decorator
    def aws_sts_assume_role_allow(self):
        client = get_client('sts')
        client.assume_role(
            RoleArn="arn:aws:iam::326190351503:role/test-role",
            RoleSessionName="org-dev-session",
        )


### S3 ###
class AwsS3Tasks(TaskSet):
    # @task(1)
    # @result_decorator
    # def aws_s3_upload_file_allow(self):
    #     bucket = os.environ['S3_TEST_BUCKET']
    #     path = f"{os.environ['S3_TEST_PATH']}/data/{''.join(random.choices(string.ascii_uppercase, k=10))}"
    #     client = get_client('s3', 'ap-southeast-2')
    #     transfer = boto3.s3.transfer.S3Transfer(client=client)
    #     transfer.upload_file('test.data', bucket, path, extra_args={'ServerSideEncryption':'aws:kms', 'SSEKMSKeyId':'alias/secure-key'} )

    @task(5)
    @result_decorator
    def aws_s3_list_objects_block(self):
        client = get_client('s3')
        client.list_objects(Bucket='kivera-poc-deployment')

    @task(1)
    @result_decorator
    def aws_s3_list_objects_allow(self):
        client = get_client('s3')
        client.get_paginator('list_objects').paginate(Bucket='kivera-poc-deployment', PaginationConfig={'MaxItems': 1})

    @task(3)
    @result_decorator
    def aws_s3_put_object_block(self):
        client = get_client('s3', 'ap-southeast-2')
        client.put_object(Bucket="test-bucket", Key="test/key", Body="test-object".encode())

    @task(1)
    @result_decorator
    def aws_s3_put_object_allow(self):
        client = get_client('s3', 'ap-southeast-2')
        client.put_object(Bucket="test-bucket", Key="test/key", Body="test-object".encode(), ServerSideEncryption='aws:kms', SSEKMSKeyId='arn:aws:kms:ap-southeast-2:326190351503:alias/secure-key')

    @task(3)
    @result_decorator
    def aws_s3_create_bucket_block(self):
        client = get_client('s3', 'ap-southeast-2')
        client.create_bucket(Bucket="test-bucket", ACL='public-read', CreateBucketConfiguration={'LocationConstraint': "ap-southeast-2"})

    @task(1)
    @result_decorator
    def aws_s3_create_bucket_allow(self):
        client = get_client('s3', 'ap-southeast-2')
        client.create_bucket(Bucket="test-bucket", ACL='private', CreateBucketConfiguration={'LocationConstraint': "ap-southeast-2"})



### APIGATEWAY ###
class AwsApiGatewayTasks(TaskSet):
    ### APIGATEWAY ###
    @task(2)
    @result_decorator
    def aws_apigateway_get_apis_allow(self):
        client = get_client('apigatewayv2')
        client.get_apis()

    # Get redis data
    @task(1)
    @result_decorator
    def aws_apigateway_get_vpc_links_allow(self):
        client = get_client('apigatewayv2')
        client.get_vpc_links()

    @task(4)
    @result_decorator
    def aws_apigateway_create_api_allow(self):
        client = get_client('apigatewayv2')
        client.create_api(Name='test-api', ProtocolType='HTTP')

    @task(4)
    @result_decorator
    def aws_apigateway_create_api_block(self):
        client = get_client('apigatewayv2')
        client.create_api(Name='test-api', ProtocolType='WEBSOCKET')

    @task(4)
    @result_decorator
    def aws_apigateway_create_route_allow(self):
        client = get_client('apigatewayv2')
        client.create_route(ApiId='api-123', RouteKey='/api/path', AuthorizerId='auth-123', AuthorizationType='AWS_IAM')

    @task(4)
    @result_decorator
    def aws_apigateway_create_route_block(self):
        client = get_client('apigatewayv2')
        client.create_route(ApiId='api-123', RouteKey='/api/path', AuthorizerId='auth-123', AuthorizationType='NONE')


### EVENTBRIDGE ###
class AwsEventBridgeTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_eventbridge_list_rules_allow(self):
        client = get_client('events')
        client.list_rules()

    @task(3)
    @result_decorator
    def aws_eventbridge_put_permission_allow(self):
        client = get_client('events')
        client.put_permission(Action='events:PutRule', Principal='326190351503')

    @task(3)
    @result_decorator
    def aws_eventbridge_put_permission_block(self):
        client = get_client('events')
        client.put_permission(Action='events:PutRule', Principal='000000000000')



### IAM ###
class AwsIamTasks(TaskSet):
    @task(4)
    @result_decorator
    def aws_iam_list_users_allow(self):
        client = get_client('iam')
        client.list_users()

    # Get redis data
    @task(1)
    @result_decorator
    def aws_iam_list_account_aliases_allow(self):
        client = get_client('iam')
        client.list_account_aliases()

    @task(2)
    @result_decorator
    def aws_iam_create_role_allow(self):
        client = get_client('iam')
        assume_role='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":["sts:AssumeRole"]}]}'
        client.create_role(RoleName='test-role', AssumeRolePolicyDocument=assume_role)

    @task(2)
    @result_decorator
    def aws_iam_create_role_block(self):
        client = get_client('iam')
        assume_role='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"000000000000"},"Action":["sts:AssumeRole"]}]}'
        client.create_role(RoleName='test-role', AssumeRolePolicyDocument=assume_role)



### RDS ###
class AwsRdsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_rds_describe_db_instances_allow(self):
        client = get_client('rds')
        client.describe_db_instances()

    @task(3)
    @result_decorator
    def aws_rds_create_db_instance_allow(self):
        client = get_client('rds')
        client.create_db_instance(DBInstanceIdentifier='test-db', DBInstanceClass='db.t3.micro', Engine='postgres', StorageEncrypted=True, KmsKeyId='alias/secure-key')

    @task(3)
    @result_decorator
    def aws_rds_create_db_instance_block(self):
        client = get_client('rds')
        client.create_db_instance(DBInstanceIdentifier='test-db', DBInstanceClass='db.t3.micro', Engine='postgres')


### CLOUDFRONT ###
class AwsCloudFrontTasks(TaskSet):
    @task(4)
    @result_decorator
    def aws_cloudfront_list_distributions_allow(self):
        client = get_client('cloudfront')
        client.list_distributions()

    # Get redis data
    @task(1)
    @result_decorator
    def aws_cloudfront_list_functions_allow(self):
        client = get_client('cloudfront')
        client.list_functions()

    @task(2)
    @result_decorator
    def aws_cloudfront_create_distribution_block(self):
        client = get_client('cloudfront')
        tmp = cloudfront_dist_config.copy()
        tmp['HttpVersion'] = "http1.1"
        client.create_distribution(DistributionConfig=tmp)

    @task(2)
    @result_decorator
    def aws_cloudfront_create_distribution_allow(self):
        client = get_client('cloudfront')
        tmp = cloudfront_dist_config.copy()
        tmp['HttpVersion'] = "http2and3"
        client.create_distribution(DistributionConfig=tmp)

    @task(4)
    @result_decorator
    def aws_cloudfront_associate_alias_block(self):
        client = get_client('cloudfront')
        client.associate_alias(TargetDistributionId='EDFDVBD6EXAMPLE', Alias='my.website.example.com')

    @task(4)
    @result_decorator
    def aws_cloudfront_associate_alias_allow(self):
        client = get_client('cloudfront')
        client.associate_alias(TargetDistributionId='EDFDVBD6EXAMPLE', Alias='my.website.kivera.io')



### SQS ###
class AwsSqsTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_sqs_create_queue_block_1(self):
        policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":"sqs:*","Resource":"*"}]}'
        client = get_client('sqs')
        client.create_queue(QueueName='test-queue', Attributes={ 'VisibilityTimeout ': '120', 'KmsMasterKeyId': 'alias/aws/sqs', 'Policy': policy } )

    @task(2)
    @result_decorator
    def aws_sqs_create_queue_block_2(self):
        policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"000000000000"},"Action":"sqs:*","Resource":"*"}]}'
        client = get_client('sqs')
        client.create_queue(QueueName='test-queue', Attributes={ 'VisibilityTimeout ': '120', 'KmsMasterKeyId': 'alias/secure-key', 'Policy': policy } )

    @task(2)
    @result_decorator
    def aws_sqs_create_queue_allow(self):
        policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":"sqs:*","Resource":"*"}]}'
        client = get_client('sqs')
        client.create_queue(QueueName='test-queue', Attributes={ 'VisibilityTimeout ': '120', 'KmsMasterKeyId': 'alias/secure-key', 'Policy': policy } )

    @task(2)
    @result_decorator
    def aws_sqs_send_message_block(self):
        client = get_client('sqs')
        client.send_message(QueueUrl='https://sqs.ap-southeast-2.amazonaws.com/000000000000/test-queue', MessageBody='test-message' )

    @task(2)
    @result_decorator
    def aws_sqs_send_message_allow(self):
        client = get_client('sqs')
        client.send_message(QueueUrl='https://sqs.ap-southeast-2.amazonaws.com/326190351503/test-queue', MessageBody='test-message' )



### LAMBDA ###
class AwsLambdaTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_lambda_create_function_block_1(self):
        client = get_client('lambda')
        client.create_function(
            FunctionName='test-lambda',
            Role='arn:aws:iam::326190351503:role/test-role',
            Code={ 'S3Bucket': 'test-bucket', 'S3Key': 'function-code'},
            Runtime='python2.7',
            VpcConfig={
                'SubnetIds': ['subnet-08ce806b357e7a444'],
                'SecurityGroupIds': ['sg-0ad587d38f88c4799']
            },
            KMSKeyArn='arn:aws:kms:ap-southeast-2:326190351503:alias/secure-key',
        )

    @task(2)
    @result_decorator
    def aws_lambda_create_function_block_2(self):
        client = get_client('lambda')
        client.create_function(
            FunctionName='test-lambda',
            Role='arn:aws:iam::326190351503:role/test-role',
            Code={ 'S3Bucket': 'test-bucket', 'S3Key': 'function-code'},
            Runtime='python3.12',
            VpcConfig={
                'SubnetIds': ['subnet-08ce806b357e7a444'],
                'SecurityGroupIds': ['sg-0ad587d38f88c4799']
            },
            KMSKeyArn='arn:aws:kms:ap-southeast-2:000000000000:alias/aws/lambda',
        )

    @task(2)
    @result_decorator
    def aws_lambda_create_function_block_3(self):
        client = get_client('lambda')
        client.create_function(
            FunctionName='test-lambda',
            Role='arn:aws:iam::326190351503:role/test-role',
            Code={ 'S3Bucket': 'test-bucket', 'S3Key': 'function-code'},
            Runtime='python3.12',
            KMSKeyArn='arn:aws:kms:ap-southeast-2:326190351503:alias/secure-key',
        )

    @task(2)
    @result_decorator
    def aws_lambda_create_function_allow(self):
        client = get_client('lambda')
        client.create_function(
            FunctionName='test-lambda',
            Role='arn:aws:iam::326190351503:role/test-role',
            Code={ 'S3Bucket': 'test-bucket', 'S3Key': 'function-code'},
            Runtime='python3.12',
            VpcConfig={
                'SubnetIds': ['subnet-08ce806b357e7a444'],
                'SecurityGroupIds': ['sg-0ad587d38f88c4799']
            },
            KMSKeyArn='arn:aws:kms:ap-southeast-2:326190351503:alias/secure-key',
        )


### LOGS ###
class AwsLogsTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_logs_create_log_group_block(self):
        client = get_client('logs', 'ap-southeast-2')
        client.create_log_group(logGroupName='test-log-group')

    @task(2)
    @result_decorator
    def aws_logs_put_subscription_filter_block(self):
        client = get_client('logs')
        client.put_subscription_filter(
            logGroupName='test-log-group',
            filterName='test-subscription',
            filterPattern='{ $.level = * }',
            roleArn='arn:aws:iam::326190351503:role/test-role',
            destinationArn='arn:aws:kinesis:us-east-1:000000000000:stream/test-stream',
        )

    @task(2)
    @result_decorator
    def aws_logs_put_subscription_filter_allow(self):
        client = get_client('logs')
        client.put_subscription_filter(
            logGroupName='test-log-group',
            filterName='test-subscription',
            filterPattern='{ $.level = * }',
            roleArn='arn:aws:iam::326190351503:role/test-role',
            destinationArn='arn:aws:kinesis:us-east-1:326190351503:stream/test-stream',
        )

    @task(2)
    @result_decorator
    def aws_logs_put_resource_policy_block(self):
        client = get_client('logs')
        policy='{"Version": "2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"000000000000"},"Action":"logs:PutLogEvents","Resource":"*"}]}'
        client.put_resource_policy(policyName='string', policyDocument=policy)

    @task(2)
    @result_decorator
    def aws_logs_put_resource_policy_allow(self):
        client = get_client('logs')
        policy='{"Version": "2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":"logs:PutLogEvents","Resource":"*"}]}'
        client.put_resource_policy(policyName='string', policyDocument=policy)



### AUTOSCALING ###
class AwsAutoScalingTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_autoscaling_describe_auto_scaling_groups_allow(self):
        client = get_client('autoscaling')
        client.describe_auto_scaling_groups()

    @task(2)
    @result_decorator
    def aws_autoscaling_create_launch_configuration_block_1(self):
        client = get_client('autoscaling')
        client.create_launch_configuration(
            LaunchConfigurationName='test-launch-config',
            ImageId='ami-0361bbf2b99f46c1d',
            InstanceType='t3.medium',
            BlockDeviceMappings=[{
                'DeviceName': '/dev/sdh',
                'Ebs': {
                    'Encrypted': False ,
                    'VolumeSize': 100,
                    'VolumeType': 'standard'
                }
            }]
        )

    @task(2)
    @result_decorator
    def aws_autoscaling_create_launch_configuration_block_2(self):
        client = get_client('autoscaling')
        client.create_launch_configuration(
            LaunchConfigurationName='test-launch-config',
            ImageId='ami-00000000000000000',
            InstanceType='t3.medium',
            BlockDeviceMappings=[{
                'DeviceName': '/dev/sdh',
                'Ebs': {
                    'Encrypted': True ,
                    'VolumeSize': 100,
                    'VolumeType': 'standard'
                }
            }]
        )

    @task(2)
    @result_decorator
    def aws_autoscaling_create_launch_configuration_allow(self):
        client = get_client('autoscaling')
        client.create_launch_configuration(
            LaunchConfigurationName='test-launch-config',
            ImageId='ami-0361bbf2b99f46c1d',
            InstanceType='t3.medium',
            BlockDeviceMappings=[{
                'DeviceName': '/dev/sdh',
                'Ebs': {
                    'Encrypted': True ,
                    'VolumeSize': 100,
                    'VolumeType': 'standard'
                }
            }]
        )


### BATCH ###
class AwsBatchTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_batch_list_jobs_allow(self):
        client = get_client('batch')
        client.list_jobs(jobQueue='my-job-queue')

    # Get redis data
    @task(1)
    @result_decorator
    def aws_batch_list_scheduling_policies_allow(self):
        client = get_client('batch')
        client.list_scheduling_policies()



### ECS ###
class AwsEcsTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_ecs_list_clusters_allow(self):
        client = get_client('ecs')
        client.list_clusters()

    # Get redis data
    @task(1)
    @result_decorator
    def aws_ecs_list_account_settings_allow(self):
        client = get_client('ecs')
        client.list_account_settings()

    @task(2)
    @result_decorator
    def aws_ecs_list_task_definitions_allow(self):
        client = get_client('ecs')
        client.list_task_definitions()



### SNS ###
class AwsSnsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_sns_list_subscriptions_allow(self):
        client = get_client('sns')
        client.list_subscriptions()

    @task(1)
    @result_decorator
    def aws_sns_list_topics_allow(self):
        client = get_client('sns')
        client.list_topics()



### CLOUDFORMATION ###
class AwsCloudFormationTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_cloudformation_describe_stacks_allow(self):
        client = get_client('cloudformation')
        client.describe_stacks()

    @task(1)
    @result_decorator
    def aws_cloudformation_describe_type_allow(self):
        type_name = secrets.choice(['AWS::EC2::VPC','AWS::Lambda::Function','AWS::EC2::Instance','AWS::S3::Bucket','AWS::KMS::Key'])
        client = get_client('cloudformation')
        client.describe_type(Type='RESOURCE', TypeName=type_name)

class AwsSensitiveFieldsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_kms_update_custom_key_store_block(self):
        client = get_client('kms')
        client.update_custom_key_store(CustomKeyStoreId='cks-1234567890abcdef0', KeyStorePassword='ExamplePassword')

    @task(1)
    @result_decorator
    def aws_workmail_reset_password_block(self):
        client = get_client('workmail')
        client.reset_password(OrganizationId='m-d281d0a2fd824be5b6cd3d3ce909fd27', UserId='S-1-1-11-1111111111-2222222222-3333333333-3333', Password='examplePa$$w0rd')

class NonCloudTasks(TaskSet):
    @task(1)
    @result_decorator
    def app_dev_block(self):
        resp = requests.get('https://app.dev.nonp.kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)

    @task(1)
    @result_decorator
    def app_stg_block(self):
        resp = requests.get('https://app.stg.nonp.kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)

    @task(1)
    @result_decorator
    def kivera_block(self):
        resp = requests.get('https://kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)

    @task(1)
    @result_decorator
    def download_block(self):
        resp = requests.get('https://download.kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)


class CustomResponseTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_xray_create_group_customresponse_block(self):
        client = get_client('xray')
        client.create_group(GroupName='test')

    @task(1)
    @result_decorator
    def aws_xray_delete_group_customresponse_block(self):
        client = get_client('xray')
        client.delete_group(GroupName='test')

    @task(1)
    @result_decorator
    def aws_xray_update_group_customresponse_block(self):
        client = get_client('xray')
        client.update_group(GroupName='test')

    @task(1)
    @result_decorator
    def aws_xray_get_group_customresponse_block(self):
        client = get_client('xray')
        client.get_group(GroupName='test')


class KiveraPerf(User):
    wait_time = between(USER_WAIT_MIN, USER_WAIT_MAX)
    tasks = {
        AwsEc2Tasks: 3,
        AwsDynamoDBTasks: 3,
        AwsStsTasks: 3,
        AwsS3Tasks: 3,
        AwsApiGatewayTasks: 3,
        AwsEventBridgeTasks: 3,
        AwsIamTasks: 2,
        AwsRdsTasks: 3,
        AwsCloudFrontTasks: 2,
        AwsSqsTasks: 3,
        AwsLambdaTasks: 3,
        AwsLogsTasks: 3,
        AwsAutoScalingTasks: 3,
        AwsBatchTasks: 3,
        AwsEcsTasks: 3,
        AwsSnsTasks: 3,
        AwsCloudFormationTasks: 3,
        AwsSensitiveFieldsTasks: 3,
        NonCloudTasks: 1,
        CustomResponseTasks: 1,
    }
