import secrets
import os
import time
import boto3
import botocore
import ddtrace
from botocore.config import Config
from locust import User, TaskSet, task, between, events
from ddtrace.propagation.http import HTTPPropagator

ddtrace.patch(botocore=True)
ddtrace.config.botocore['distributed_tracing'] = False

client_config = Config(
   connect_timeout=3,
   retries = {
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

boto3.setup_default_session(region_name='ap-southeast-2')

USER_WAIT_MIN = int(os.getenv('USER_WAIT_MIN', 4))
USER_WAIT_MAX = int(os.getenv('USER_WAIT_MAX', 6))

def add_trace_headers(request, **kwargs):
    span = ddtrace.tracer.current_span()
    span.service = "locust"
    headers = {}
    HTTPPropagator.inject(span.context, headers)
    for h, v in headers.items():
        request.headers.add_header(h, v)

def get_client(service, region=""):
    if region == "":
        region = secrets.choice(aws_regions)
    client = boto3.client(service, region_name=region, config=client_config)
    client.meta.events.register_first('before-sign.*.*', add_trace_headers)
    return client

def result_decorator(method):
    def decorator(self):
        class_name = self.__class__.__name__
        method_name = method.__name__
        method_parts = method_name.split('_')
        validity = method_parts[-1]
        if validity.isnumeric():
            validity = method_parts[-2]
        else:
            validity = method_parts[-1]
        if validity == 'allow':
            should_block = False
        elif validity == 'block':
            should_block = True
        else:
            return failure(class_name, method_name, time.time(), Exception("method name must end with '_block' or '_allow'"))

        start_time = time.time()
        try:
            method(self)

        except botocore.exceptions.ClientError as error:
            # If error code is allowed, treat as a successful request
            if not should_block and error.response['Error']['Code'] in allowed_errors:
                return success(class_name, method_name, start_time)
            # otherwise check for Kivera error
            return check_err_message(should_block, class_name, method_name, start_time, error)

        except Exception as error:
            # check for Kivera error
            return check_err_message(should_block, class_name, method_name, start_time, error)

        # on successful request
        if should_block:
            return failure(class_name, method_name, start_time, Exception("API call should have been blocked by Kivera"))
        return success(class_name, method_name, start_time)

    return decorator

def check_err_message(should_block, class_name, method_name, start_time, error):
    if should_block and "Kivera.Error" in str(error) and "Oops, your request has been blocked." in str(error):
        return success(class_name, method_name, start_time)
    return failure(class_name, method_name, start_time, error)

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

### S3 ###
class AwsS3Tasks(TaskSet):
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
    def aws_s3_get_object_allow_1(self):
        client = get_client('s3', 'ap-southeast-2')
        client.get_object(Bucket="kivera-poc-deployment", Key="kivera/locust-perf-test/file-01/data.txt")

    @task(1)
    @result_decorator
    def aws_s3_get_object_allow_2(self):
        client = get_client('s3', 'ap-southeast-2')
        client.get_object(Bucket="kivera-poc-deployment", Key="kivera/locust-perf-test/file-02/data.txt")

    @task(1)
    @result_decorator
    def aws_s3_get_object_allow_3(self):
        client = get_client('s3', 'ap-southeast-2')
        client.get_object(Bucket="kivera-poc-deployment", Key="kivera/locust-perf-test/file-03/data.txt")

class KiveraPerf(User):
    wait_time = between(USER_WAIT_MIN, USER_WAIT_MAX)
    tasks = {
        AwsS3Tasks: 1
    }
