import time
import boto3
import botocore
from locust import User, TaskSet, task, between, events

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

boto3.setup_default_session(region_name='ap-southeast-2')

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
    @task
    @result_decorator
    def aws_s3_get_object_allow(self):
        s3 = boto3.resource('s3')
        s3.meta.client.download_file("kivera-poc-deployment", "kivera/locust-perf-test/ubuntu-22.04.4-desktop-amd64.iso", "/root/kivera/ubuntu.iso")

class KiveraPerf(User):
    wait_time = between(70, 90)
    tasks = {
        AwsS3Tasks: 1
    }
