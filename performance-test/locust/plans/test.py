import secrets
import os
import time
import random
import threading
import concurrent.futures
import queue
import boto3
import botocore
import ddtrace
from botocore.config import Config
from locust import User, TaskSet, task, between, events
from ddtrace.propagation.http import HTTPPropagator
import requests
import urllib3

urllib3.disable_warnings(category=urllib3.exceptions.InsecureRequestWarning)

req_session = requests.Session()

class TimeoutException(Exception):
    pass

USER_WAIT_MIN = int(os.getenv('USER_WAIT_MIN', '4'))
USER_WAIT_MAX = int(os.getenv('USER_WAIT_MAX', '6'))
TEST_TIMEOUT = int(os.getenv('TEST_TIMEOUT', '60'))

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

ddtrace.patch(botocore=True)
ddtrace.config.botocore['distributed_tracing'] = False

all_clients = {}
all_clients_lock = threading.Lock()

def get_client(service, region=""):
    if region == "":
        region = secrets.choice(aws_regions)

    client = boto3.client(service, region_name=region, config=client_config)
    client.meta.events.register_first('before-sign.*.*', add_trace_headers)
    return client

class ClientPool:
    def __init__(self):
        self.pool = {}
        self.lock = threading.Lock()

    def new_client(self, service, region="ap-southeast-2"):
        client = boto3.client(service, region_name=region, config=client_config)
        client.meta.events.register_first('before-sign.*.*', add_trace_headers)
        return client

    def get(self, service, region="ap-southeast-2"):
        with self.lock:
            if service not in self.pool:
                self.pool[service] = {}
            if region not in self.pool[service]:
                self.pool[service][region] = queue.SimpleQueue()

        try:
            return self.pool[service][region].get_nowait()
        except queue.Empty:
            return self.new_client(service, region)

    def put(self, obj, service, region="ap-southeast-2"):
        self.pool[service][region].put(obj)


client_pool = ClientPool()

client_config = Config(
    # connect_timeout = 10,
    # read_timeout = 30,
    # tcp_keepalive = True,
    retries = {
        'total_max_attempts': 1,
        'mode': 'standard'
    }
)

allowed_errors = [
    # 'AccessDenied',
    # 'AccessDeniedException',
    # 'UnauthorizedOperation',
    # 'InvalidClientTokenId',
    # 'UnrecognizedClientException',
    # 'AuthFailure',

    # 'AWS.SimpleQueueService.NonExistentQueue',

    # 'Throttling',
    # 'ThrottlingException',
    # 'ThrottledException',
    # 'RequestThrottledException',
    # 'TooManyRequestsException',
    # 'ProvisionedThroughputExceededException',
    # 'TransactionInProgressException',
    # 'RequestLimitExceeded',
    # 'BandwidthLimitExceeded',
    # 'LimitExceededException',
    # 'RequestThrottled',
    # 'SlowDown',
    # 'EC2ThrottledException',

    # 'KMS.NotFoundException',
    # 'ClusterNotFoundException',
    # 'ValidationError',
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

def add_trace_headers(request, **kwargs):
    span = ddtrace.tracer.current_span()
    span.service = "locust"
    headers = {}
    HTTPPropagator.inject(span.context, headers)
    for h, v in headers.items():
        request.headers.add_header(h, v)


def action_name(parts):
    action = ""
    for p in parts:
        action += p.title()
    return action

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
            idx = idx-1

        provider = method_parts[0].upper()
        if provider == "NONCLOUD":
            should_contain = "Host:"
        else:
            service = method_parts[1].upper()
            action = action_name(method_parts[2:idx])
            should_contain = f"Provider:{provider}, Service:{service}, Action:{action}"

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
                future.result(timeout=TEST_TIMEOUT)

        except concurrent.futures.TimeoutError:
            return failure(class_name, method_name, start_time, TimeoutException(f"Timeout ({TEST_TIMEOUT}s) exceeded"))

        except botocore.exceptions.ClientError as error:
            # If error code is allowed, treat as a successful request
            if not should_block and error.response['Error']['Code'] in allowed_errors:
                return success(class_name, method_name, start_time)
            # otherwise check for Kivera error
            return check_err_message(should_block, should_contain, custom_resp, class_name, method_name, start_time, error)

        except Exception as error:
            # check for Kivera error
            return check_err_message(should_block, should_contain, custom_resp, class_name, method_name, start_time, error)

        # on successful request
        if should_block:
            return failure(class_name, method_name, start_time, Exception("API call should have been blocked by Kivera"))

        return success(class_name, method_name, start_time)

    return decorator

def check_err_message(should_block, should_contain, custom_resp, class_name, method_name, start_time, error):

    if not should_block:
        return failure(class_name, method_name, start_time, error)

    if "Kivera.Error" not in str(error) and "Oops, your request has been blocked." not in str(error):
        return failure(class_name, method_name, start_time, Exception("Request Not Blocked: got" + str(error)))

    if should_contain.lower() not in str(error).lower():
        return failure(class_name, method_name, start_time, Exception(f"Incorrect Response: {should_contain}: got {str(error)}"))

    if custom_resp:
        expected = custom_responses[class_name][method_name]
        if not contains_custom_response(error, expected):
            return failure(class_name, method_name, start_time, Exception(f"Missing Custom Response: '{expected}': got {str(error)}"))

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
        client = client_pool.get('ec2')
        client.describe_instances()
        client_pool.put(client, 'ec2')

    @task(1)
    @result_decorator
    def aws_ec2_describe_instances_allow(self):
        client = client_pool.get('ec2')
        client.get_paginator('describe_instances').paginate(PaginationConfig={'MaxItems': 1})
        client_pool.put(client, 'ec2')


    @task(3)
    @result_decorator
    def aws_ec2_authorize_security_group_ingress_block(self):
        client = client_pool.get('ec2')
        client.authorize_security_group_ingress(
            CidrIp='0.0.0.0/0',
            ToPort=22,
            FromPort=22,
            IpProtocol="TCP",
            GroupId="sg-09a320fc24c2fd3c5",
        )
        client_pool.put(client, 'ec2')

    @task(2)
    @result_decorator
    def aws_ec2_create_key_pair_block(self):
        client = client_pool.get('ec2')
        client.create_key_pair(KeyName='test-key-pair', KeyType='rsa', KeyFormat='pem' )
        client_pool.put(client, 'ec2')

    @task(2)
    @result_decorator
    def aws_ec2_create_key_pair_allow(self):
        client = client_pool.get('ec2')
        client.create_key_pair(KeyName='test-key-pair', KeyType='ed25519', KeyFormat='pem' )
        client_pool.put(client, 'ec2')

    @task(2)
    @result_decorator
    def aws_ec2_create_volume_block(self):
        client = client_pool.get('ec2')
        client.create_volume(AvailabilityZone="ap-southeast-2a", Encrypted=False)
        client_pool.put(client, 'ec2')

    @task(1)
    @result_decorator
    def aws_ec2_create_volume_allow(self):
        client = client_pool.get('ec2')
        client.create_volume(AvailabilityZone="ap-southeast-2a", Encrypted=True, KmsKeyId='alias/secure-key', Size=100)
        client_pool.put(client, 'ec2')



### DYNAMODB ###
class AwsDynamoDBTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_dynamodb_list_tables_allow(self):
        client = client_pool.get('dynamodb')
        client.list_tables()
        client_pool.put(client, 'dynamodb')

    @task(3)
    @result_decorator
    def aws_dynamodb_create_table_block(self):
        client = client_pool.get('dynamodb')
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
        client_pool.put(client, 'dynamodb')

    @task(3)
    @result_decorator
    def aws_dynamodb_create_table_allow(self):
        client = client_pool.get('dynamodb')
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
        client_pool.put(client, 'dynamodb')



### STS ###
class AwsStsTasks(TaskSet):
    @task(4)
    @result_decorator
    def aws_sts_get_caller_identity_allow(self):
        client = client_pool.get('sts')
        client.get_caller_identity()
        client_pool.put(client, 'sts')

    @task(2)
    @result_decorator
    def aws_sts_assume_role_block_1(self):
        client = client_pool.get('sts')
        client.assume_role(
            RoleArn="arn:aws:iam::326190351503:role/test-role",
            RoleSessionName="invalid-session-name",
        )
        client_pool.put(client, 'sts')

    @task(2)
    @result_decorator
    def aws_sts_assume_role_block_2(self):
        client = client_pool.get('sts')
        client.assume_role(
            RoleArn="arn:aws:iam::000000000000:role/test-role",
            RoleSessionName="org-dev-session",
        )
        client_pool.put(client, 'sts')

    @task(4)
    @result_decorator
    def aws_sts_assume_role_allow(self):
        client = client_pool.get('sts')
        client.assume_role(
            RoleArn="arn:aws:iam::326190351503:role/test-role",
            RoleSessionName="org-dev-session",
        )
        client_pool.put(client, 'sts')

    # set redis data
    @task(1)
    @result_decorator
    def aws_sts_get_access_key_info_allow(self):
        client = client_pool.get('sts')
        client.get_access_key_info(AccessKeyId="somethingtokenss")
        client_pool.put(client, 'sts')

    # set_with_options redis data
    @task(1)
    @result_decorator
    def aws_sts_get_federation_token_allow(self):
        client = client_pool.get('sts')
        client.get_federation_token(Name="something")
        client_pool.put(client, 'sts')

    # get both redis data
    @task(1)
    @result_decorator
    def aws_sts_get_session_token_allow(self):
        client = client_pool.get('sts')
        client.get_session_token()
        client_pool.put(client, 'sts')


### S3 ###
class AwsS3Tasks(TaskSet):
    # @task(1)
    # @result_decorator
    # def aws_s3_upload_file_allow(self):
    #     bucket = os.environ['S3_TEST_BUCKET']
    #     path = f"{os.environ['S3_TEST_PATH']}/data/{''.join(random.choices(string.ascii_uppercase, k=10))}"
    #     client = client_pool.get('s3')
    #     transfer = boto3.s3.transfer.S3Transfer(client=client)
    #     transfer.upload_file('test.data', bucket, path, extra_args={'ServerSideEncryption':'aws:kms', 'SSEKMSKeyId':'alias/secure-key'} )

    @task(5)
    @result_decorator
    def aws_s3_list_objects_block(self):
        client = client_pool.get('s3')
        client.list_objects(Bucket='kivera-poc-deployment')
        client_pool.put(client, 's3')

    @task(1)
    @result_decorator
    def aws_s3_list_objects_allow(self):
        client = client_pool.get('s3')
        client.get_paginator('list_objects').paginate(Bucket='kivera-poc-deployment', PaginationConfig={'MaxItems': 1})
        client_pool.put(client, 's3')

    @task(3)
    @result_decorator
    def aws_s3_put_object_block(self):
        client = client_pool.get('s3')
        client.put_object(Bucket="test-bucket", Key="test/key", Body="test-object".encode())
        client_pool.put(client, 's3')

    @task(1)
    @result_decorator
    def aws_s3_put_object_allow(self):
        client = client_pool.get('s3')
        client.put_object(Bucket="test-bucket", Key="test/key", Body="test-object".encode(), ServerSideEncryption='aws:kms', SSEKMSKeyId='arn:aws:kms:ap-southeast-2:326190351503:alias/secure-key')
        client_pool.put(client, 's3')

    @task(3)
    @result_decorator
    def aws_s3_create_bucket_block(self):
        client = client_pool.get('s3')
        client.create_bucket(Bucket="test-bucket", ACL='public-read', CreateBucketConfiguration={'LocationConstraint': "ap-southeast-2"})
        client_pool.put(client, 's3')

    @task(1)
    @result_decorator
    def aws_s3_create_bucket_allow(self):
        client = client_pool.get('s3')
        client.create_bucket(Bucket="test-bucket", ACL='private', CreateBucketConfiguration={'LocationConstraint': "ap-southeast-2"})
        client_pool.put(client, 's3')



### APIGATEWAY ###
class AwsApiGatewayTasks(TaskSet):
    # delete redis data
    @task(1)
    @result_decorator
    def aws_apigateway_get_sdk_types_allow(self):
        client = client_pool.get('apigateway')
        client.get_sdk_types()
        client_pool.put(client, 'apigateway')

    # set_with_options redis data
    @task(1)
    @result_decorator
    def aws_apigateway_get_apis_allow(self):
        client = client_pool.get('apigatewayv2')
        client.get_apis()
        client_pool.put(client, 'apigatewayv2')

    # get both redis data
    @task(1)
    @result_decorator
    def aws_apigateway_get_vpc_links_allow(self):
        client = client_pool.get('apigatewayv2')
        client.get_vpc_links()
        client_pool.put(client, 'apigatewayv2')

    # set redis data
    @task(1)
    @result_decorator
    def aws_apigateway_get_domain_names_allow(self):
        client = client_pool.get('apigatewayv2')
        client.get_domain_names()
        client_pool.put(client, 'apigatewayv2')

    @task(4)
    @result_decorator
    def aws_apigateway_create_api_allow(self):
        client = client_pool.get('apigatewayv2')
        client.create_api(Name='test-api', ProtocolType='HTTP')
        client_pool.put(client, 'apigatewayv2')

    @task(4)
    @result_decorator
    def aws_apigateway_create_api_block(self):
        client = client_pool.get('apigatewayv2')
        client.create_api(Name='test-api', ProtocolType='WEBSOCKET')
        client_pool.put(client, 'apigatewayv2')

    @task(4)
    @result_decorator
    def aws_apigateway_create_route_allow(self):
        client = client_pool.get('apigatewayv2')
        client.create_route(ApiId='api-123', RouteKey='/api/path', AuthorizerId='auth-123', AuthorizationType='AWS_IAM')
        client_pool.put(client, 'apigatewayv2')

    @task(4)
    @result_decorator
    def aws_apigateway_create_route_block(self):
        client = client_pool.get('apigatewayv2')
        client.create_route(ApiId='api-123', RouteKey='/api/path', AuthorizerId='auth-123', AuthorizationType='NONE')
        client_pool.put(client, 'apigatewayv2')


### EVENTBRIDGE ###
class AwsEventsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_events_list_rules_allow(self):
        client = client_pool.get('events')
        client.list_rules()
        client_pool.put(client, 'events')

    @task(3)
    @result_decorator
    def aws_events_put_permission_allow(self):
        client = client_pool.get('events')
        client.put_permission(Action='events:PutRule', Principal='326190351503')
        client_pool.put(client, 'events')

    @task(3)
    @result_decorator
    def aws_events_put_permission_block(self):
        client = client_pool.get('events')
        client.put_permission(Action='events:PutRule', Principal='000000000000')
        client_pool.put(client, 'events')



### IAM ###
class AwsIamTasks(TaskSet):
    @task(4)
    @result_decorator
    def aws_iam_list_users_allow(self):
        client = client_pool.get('iam')
        client.list_users()
        client_pool.put(client, 'iam')

    # delete redis data
    @task(1)
    @result_decorator
    def aws_iam_list_instance_profiles_allow(self):
        client = client_pool.get('iam')
        client.list_instance_profiles()
        client_pool.put(client, 'iam')

    # get redis data
    @task(1)
    @result_decorator
    def aws_iam_list_account_aliases_allow(self):
        client = client_pool.get('iam')
        client.list_account_aliases()
        client_pool.put(client, 'iam')

    # set_with_options redis data
    @task(1)
    @result_decorator
    def aws_iam_list_groups_allow(self):
        client = client_pool.get('iam')
        client.list_groups()
        client_pool.put(client, 'iam')

    # set redis data
    @task(1)
    @result_decorator
    def aws_iam_list_roles_allow(self):
        client = client_pool.get('iam')
        client.list_roles()
        client_pool.put(client, 'iam')

    @task(2)
    @result_decorator
    def aws_iam_create_role_allow(self):
        client = client_pool.get('iam')
        assume_role='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":["sts:AssumeRole"]}]}'
        client.create_role(RoleName='test-role', AssumeRolePolicyDocument=assume_role)
        client_pool.put(client, 'iam')

    @task(2)
    @result_decorator
    def aws_iam_create_role_block(self):
        client = client_pool.get('iam')
        assume_role='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"000000000000"},"Action":["sts:AssumeRole"]}]}'
        client.create_role(RoleName='test-role', AssumeRolePolicyDocument=assume_role)
        client_pool.put(client, 'iam')



### RDS ###
class AwsRdsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_rds_describe_db_instances_allow(self):
        client = client_pool.get('rds')
        client.describe_db_instances()
        client_pool.put(client, 'rds')

    @task(3)
    @result_decorator
    def aws_rds_create_db_instance_allow(self):
        client = client_pool.get('rds')
        client.create_db_instance(DBInstanceIdentifier='test-db', DBInstanceClass='db.t3.micro', Engine='postgres', StorageEncrypted=True, KmsKeyId='alias/secure-key')
        client_pool.put(client, 'rds')

    @task(3)
    @result_decorator
    def aws_rds_create_db_instance_block(self):
        client = client_pool.get('rds')
        client.create_db_instance(DBInstanceIdentifier='test-db', DBInstanceClass='db.t3.micro', Engine='postgres')
        client_pool.put(client, 'rds')


### CLOUDFRONT ###
class AwsCloudFrontTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_cloudfront_create_distribution_block(self):
        client = client_pool.get('cloudfront')
        tmp = cloudfront_dist_config.copy()
        tmp['HttpVersion'] = "http1.1"
        client.create_distribution(DistributionConfig=tmp)
        client_pool.put(client, 'cloudfront')

    @task(2)
    @result_decorator
    def aws_cloudfront_create_distribution_allow(self):
        client = client_pool.get('cloudfront')
        tmp = cloudfront_dist_config.copy()
        tmp['HttpVersion'] = "http2and3"
        client.create_distribution(DistributionConfig=tmp)
        client_pool.put(client, 'cloudfront')

    @task(4)
    @result_decorator
    def aws_cloudfront_associate_alias_block(self):
        client = client_pool.get('cloudfront')
        client.associate_alias(TargetDistributionId='EDFDVBD6EXAMPLE', Alias='my.website.example.com')
        client_pool.put(client, 'cloudfront')

    @task(4)
    @result_decorator
    def aws_cloudfront_associate_alias_allow(self):
        client = client_pool.get('cloudfront')
        client.associate_alias(TargetDistributionId='EDFDVBD6EXAMPLE', Alias='my.website.kivera.io')
        client_pool.put(client, 'cloudfront')



### SQS ###
class AwsSqsTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_sqs_create_queue_block_1(self):
        policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":"sqs:*","Resource":"*"}]}'
        client = client_pool.get('sqs')
        client.create_queue(QueueName='test-queue', Attributes={ 'VisibilityTimeout ': '120', 'KmsMasterKeyId': 'alias/aws/sqs', 'Policy': policy } )
        client_pool.put(client, 'sqs')

    @task(2)
    @result_decorator
    def aws_sqs_create_queue_block_2(self):
        policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"000000000000"},"Action":"sqs:*","Resource":"*"}]}'
        client = client_pool.get('sqs')
        client.create_queue(QueueName='test-queue', Attributes={ 'VisibilityTimeout ': '120', 'KmsMasterKeyId': 'alias/secure-key', 'Policy': policy } )
        client_pool.put(client, 'sqs')

    @task(2)
    @result_decorator
    def aws_sqs_create_queue_allow(self):
        policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":"sqs:*","Resource":"*"}]}'
        client = client_pool.get('sqs')
        client.create_queue(QueueName='test-queue', Attributes={ 'VisibilityTimeout ': '120', 'KmsMasterKeyId': 'alias/secure-key', 'Policy': policy } )
        client_pool.put(client, 'sqs')

    @task(2)
    @result_decorator
    def aws_sqs_send_message_block(self):
        client = client_pool.get('sqs')
        client.send_message(QueueUrl='https://sqs.ap-southeast-2.amazonaws.com/000000000000/test-queue', MessageBody='test-message' )
        client_pool.put(client, 'sqs')

    @task(2)
    @result_decorator
    def aws_sqs_send_message_allow(self):
        client = client_pool.get('sqs')
        client.send_message(QueueUrl='https://sqs.ap-southeast-2.amazonaws.com/326190351503/test-queue', MessageBody='test-message' )
        client_pool.put(client, 'sqs')



### LAMBDA ###
class AwsLambdaTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_lambda_create_function_block_1(self):
        client = client_pool.get('lambda')
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
        client_pool.put(client, 'lambda')

    @task(2)
    @result_decorator
    def aws_lambda_create_function_block_2(self):
        client = client_pool.get('lambda')
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
        client_pool.put(client, 'lambda')

    @task(2)
    @result_decorator
    def aws_lambda_create_function_block_3(self):
        client = client_pool.get('lambda')
        client.create_function(
            FunctionName='test-lambda',
            Role='arn:aws:iam::326190351503:role/test-role',
            Code={ 'S3Bucket': 'test-bucket', 'S3Key': 'function-code'},
            Runtime='python3.12',
            KMSKeyArn='arn:aws:kms:ap-southeast-2:326190351503:alias/secure-key',
        )
        client_pool.put(client, 'lambda')

    @task(2)
    @result_decorator
    def aws_lambda_create_function_allow(self):
        client = client_pool.get('lambda')
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
        client_pool.put(client, 'lambda')


### LOGS ###
class AwsLogsTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_logs_create_log_group_block(self):
        client = client_pool.get('logs')
        client.create_log_group(logGroupName='test-log-group')
        client_pool.put(client, 'logs')

    @task(2)
    @result_decorator
    def aws_logs_put_subscription_filter_block(self):
        client = client_pool.get('logs')
        client.put_subscription_filter(
            logGroupName='test-log-group',
            filterName='test-subscription',
            filterPattern='{ $.level = * }',
            roleArn='arn:aws:iam::326190351503:role/test-role',
            destinationArn='arn:aws:kinesis:us-east-1:000000000000:stream/test-stream',
        )
        client_pool.put(client, 'logs')

    @task(2)
    @result_decorator
    def aws_logs_put_subscription_filter_allow(self):
        client = client_pool.get('logs')
        client.put_subscription_filter(
            logGroupName='test-log-group',
            filterName='test-subscription',
            filterPattern='{ $.level = * }',
            roleArn='arn:aws:iam::326190351503:role/test-role',
            destinationArn='arn:aws:kinesis:us-east-1:326190351503:stream/test-stream',
        )
        client_pool.put(client, 'logs')

    @task(2)
    @result_decorator
    def aws_logs_put_resource_policy_block(self):
        client = client_pool.get('logs')
        policy='{"Version": "2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"000000000000"},"Action":"logs:PutLogEvents","Resource":"*"}]}'
        client.put_resource_policy(policyName='string', policyDocument=policy)
        client_pool.put(client, 'logs')

    @task(2)
    @result_decorator
    def aws_logs_put_resource_policy_allow(self):
        client = client_pool.get('logs')
        policy='{"Version": "2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"326190351503"},"Action":"logs:PutLogEvents","Resource":"*"}]}'
        client.put_resource_policy(policyName='string', policyDocument=policy)
        client_pool.put(client, 'logs')



### AUTOSCALING ###
class AwsAutoScalingTasks(TaskSet):
    @task(2)
    @result_decorator
    def aws_autoscaling_describe_auto_scaling_groups_allow(self):
        client = client_pool.get('autoscaling')
        client.describe_auto_scaling_groups()
        client_pool.put(client, 'autoscaling')

    @task(2)
    @result_decorator
    def aws_autoscaling_create_launch_configuration_block_1(self):
        client = client_pool.get('autoscaling')
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
        client_pool.put(client, 'autoscaling')

    @task(2)
    @result_decorator
    def aws_autoscaling_create_launch_configuration_block_2(self):
        client = client_pool.get('autoscaling')
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
        client_pool.put(client, 'autoscaling')

    @task(2)
    @result_decorator
    def aws_autoscaling_create_launch_configuration_allow(self):
        client = client_pool.get('autoscaling')
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
        client_pool.put(client, 'autoscaling')


### BATCH ###
class AwsBatchTasks(TaskSet):
    # set_with_options redis data
    @task(1)
    @result_decorator
    def aws_batch_delete_jobs_queue_allow(self):
        client = client_pool.get('batch')
        client.delete_job_queue(jobQueue='random-something')
        client_pool.put(client, 'batch')

    # get both redis data
    @task(1)
    @result_decorator
    def aws_batch_list_scheduling_policies_allow(self):
        client = client_pool.get('batch')
        client.list_scheduling_policies()
        client_pool.put(client, 'batch')

    @task(4)
    @result_decorator
    def aws_batch_list_jobs_allow(self):
        client = client_pool.get('batch')
        client.list_jobs(jobQueue='my-job-queue')
        client_pool.put(client, 'batch')

    # set redis data
    @task(1)
    @result_decorator
    def aws_batch_describe_jobs_allow(self):
        client = client_pool.get('batch')
        client.describe_jobs(jobs=["my-job-queue"])
        client_pool.put(client, 'batch')



### ECS ###
class AwsEcsTasks(TaskSet):
    # delete redis data
    @task(1)
    @result_decorator
    def aws_ecs_describe_clusters_allow(self):
        client = client_pool.get('ecs')
        client.describe_clusters()
        client_pool.put(client, 'ecs')

    @task(4)
    @result_decorator
    def aws_ecs_list_clusters_allow(self):
        client = client_pool.get('ecs')
        client.list_clusters()
        client_pool.put(client, 'ecs')

    # get both redis data
    @task(1)
    @result_decorator
    def aws_ecs_list_account_settings_allow(self):
        client = client_pool.get('ecs')
        client.list_account_settings()
        client_pool.put(client, 'ecs')

    # set_with_options redis data
    @task(1)
    @result_decorator
    def aws_ecs_list_task_definitions_allow(self):
        client = client_pool.get('ecs')
        client.list_task_definitions()
        client_pool.put(client, 'ecs')

    # set redis data
    @task(1)
    @result_decorator
    def aws_ecs_list_attributes_allow(self):
        client = client_pool.get('ecs')
        client.list_attributes(targetType='container-instance')
        client_pool.put(client, 'ecs')

### SNS ###
class AwsSnsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_sns_list_subscriptions_allow(self):
        client = client_pool.get('sns')
        client.list_subscriptions()
        client_pool.put(client, 'sns')

    @task(1)
    @result_decorator
    def aws_sns_list_topics_allow(self):
        client = client_pool.get('sns')
        client.list_topics()
        client_pool.put(client, 'sns')



### CLOUDFORMATION ###
class AwsCloudFormationTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_cloudformation_describe_stacks_allow(self):
        client = client_pool.get('cloudformation')
        client.describe_stacks()
        client_pool.put(client, 'cloudformation')

    @task(1)
    @result_decorator
    def aws_cloudformation_describe_type_allow(self):
        type_name = secrets.choice(['AWS::EC2::VPC','AWS::Lambda::Function','AWS::EC2::Instance','AWS::S3::Bucket','AWS::KMS::Key'])
        client = client_pool.get('cloudformation')
        client.describe_type(Type='RESOURCE', TypeName=type_name)
        client_pool.put(client, 'cloudformation')

class AwsSensitiveFieldsTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_kms_update_custom_key_store_block(self):
        client = client_pool.get('kms')
        client.update_custom_key_store(CustomKeyStoreId='cks-1234567890abcdef0', KeyStorePassword='ExamplePassword')
        client_pool.put(client, 'kms')

    @task(1)
    @result_decorator
    def aws_workmail_reset_password_block(self):
        client = client_pool.get('workmail')
        client.reset_password(OrganizationId='m-d281d0a2fd824be5b6cd3d3ce909fd27', UserId='S-1-1-11-1111111111-2222222222-3333333333-3333', Password='examplePa$$w0rd')
        client_pool.put(client, 'workmail')

class NonCloudTasks(TaskSet):
    @task(1)
    @result_decorator
    def noncloud_app_dev_block(self):
        resp = req_session.get('https://app.dev.nonp.kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)

    @task(1)
    @result_decorator
    def noncloud_app_stg_block(self):
        resp = req_session.get('https://app.stg.nonp.kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)

    @task(1)
    @result_decorator
    def noncloud_kivera_block(self):
        resp = req_session.get('https://kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)

    @task(1)
    @result_decorator
    def noncloud_download_block(self):
        resp = req_session.get('https://download.kivera.io')
        if resp.status_code != 200:
            raise Exception(resp.text)


class CustomResponseTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_xray_create_group_customresponse_block(self):
        client = client_pool.get('xray')
        client.create_group(GroupName='test')
        client_pool.put(client, 'xray')

    @task(1)
    @result_decorator
    def aws_xray_delete_group_customresponse_block(self):
        client = client_pool.get('xray')
        client.delete_group(GroupName='test')
        client_pool.put(client, 'xray')

    @task(1)
    @result_decorator
    def aws_xray_update_group_customresponse_block(self):
        client = client_pool.get('xray')
        client.update_group(GroupName='test')
        client_pool.put(client, 'xray')

    @task(1)
    @result_decorator
    def aws_xray_get_group_customresponse_block(self):
        client = client_pool.get('xray')
        client.get_group(GroupName='test')
        client_pool.put(client, 'xray')

class ThroughputTasksCloud(TaskSet):
    @task(1)
    @result_decorator
    def aws_s3_get_object_allow(self):
        client = get_client("s3", "ap-southeast-2")
        # client = client_pool.get('s3')
        with open("/root/kivera/ubuntu.s3.iso", "wb") as f:
            client.download_fileobj(
                "kivera-poc-deployment",
                "kivera/locust-perf-test/ubuntu-22.04.4-desktop-amd64.iso",
                f,
            )
        # client_pool.put(client, 's3')

class ThroughputTasksNonCloud(TaskSet):
    @task(1)
    @result_decorator
    def noncloud_download_allow(self):
        r = req_session.get("https://releases.ubuntu.com/jammy/ubuntu-22.04.5-desktop-amd64.iso", allow_redirects=True)
        open('/root/kivera/ubuntu.iso', 'wb').write(r.content)

class ThroughputCloud(User):
    wait_time = between(USER_WAIT_MIN, USER_WAIT_MAX)
    tasks = {
        ThroughputTasksCloud: 1
    }

class ThroughputNonCloud(User):
    wait_time = between(USER_WAIT_MIN, USER_WAIT_MAX)
    tasks = {
        ThroughputTasksNonCloud: 1
    }

class TransparentProxyTasks(TaskSet):
    @task(1)
    @result_decorator
    def aws_s3_list_objects_allow(self):
        client = client_pool.get('s3')
        client.get_paginator('list_objects').paginate(Bucket='kivera-poc-deployment', PaginationConfig={'MaxItems': 1})
        client_pool.put(client, 's3')

    @task(3)
    @result_decorator
    def aws_s3_put_object_block(self):
        client = client_pool.get('s3')
        client.put_object(Bucket="test-bucket", Key="test/key", Body="test-object".encode())
        client_pool.put(client, 's3')

    @task(1)
    @result_decorator
    def aws_s3_get_object_allow_1(self):
        client = client_pool.get('s3')
        client.get_object(Bucket="kivera-poc-deployment", Key="kivera/locust-perf-test/file-01/data.txt")
        client_pool.put(client, 's3')

    @task(1)
    @result_decorator
    def aws_s3_get_object_allow_2(self):
        client = client_pool.get('s3')
        client.get_object(Bucket="kivera-poc-deployment", Key="kivera/locust-perf-test/file-02/data.txt")
        client_pool.put(client, 's3')

    @task(1)
    @result_decorator
    def aws_s3_get_object_allow_3(self):
        client = client_pool.get('s3')
        client.get_object(Bucket="kivera-poc-deployment", Key="kivera/locust-perf-test/file-03/data.txt")
        client_pool.put(client, 's3')


class Transparent(User):
    wait_time = between(USER_WAIT_MIN, USER_WAIT_MAX)
    tasks = {
        TransparentProxyTasks: 1,
    }


class Standard(User):
    wait_time = between(USER_WAIT_MIN, USER_WAIT_MAX)
    tasks = {
        AwsEc2Tasks: 3,
        AwsDynamoDBTasks: 3,
        AwsStsTasks: 3,
        AwsS3Tasks: 3,
        AwsApiGatewayTasks: 3,
        AwsEventsTasks: 3,
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
