#!/bin/bash
set -x

## tune box
echo "* hard nofile 100000" >> /etc/security/limits.conf
echo "* soft nofile 100000" >> /etc/security/limits.conf
echo "net.core.somaxconn=16384" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog=1000" >> /etc/sysctl.conf
sysctl -p

mkdir -p ~/kivera

if [[ ${proxy_transparent_enabled} == true ]]; then
    echo "${proxy_public_cert}" > ~/kivera/ca-cert.pem
else
    time=180
    echo Polling http://${proxy_endpoint}:8090/version
    while ! curl -s http://${proxy_endpoint}:8090/version; do
        [[ $time == 0 ]] && echo "Failed to get response" && exit 1
        ((time-=1)); sleep 1;
    done

    # curl -s http://${proxy_endpoint}:8090/pub.cert > ~/kivera/ca-cert.pem
    echo "${proxy_public_cert}" > ~/kivera/ca-cert.pem

    echo "
    export HTTPS_PROXY=\"${proxy_protocol}://${proxy_endpoint}:8080\"
    export HTTP_PROXY=\"${proxy_protocol}://${proxy_endpoint}:8080\"
    export https_proxy=\"${proxy_protocol}://${proxy_endpoint}:8080\"
    export http_proxy=\"${proxy_protocol}://${proxy_endpoint}:8080\"
    export NO_PROXY=\"${leader_ip},${proxy_endpoint},169.254.169.254,.github.com\"
    export no_proxy=\"\$NO_PROXY\"
    " >> ~/kivera/setenv.sh
fi

cp ~/kivera/ca-cert.pem /etc/pki/ca-trust/source/anchors/ca-cert.pem
update-ca-trust extract

echo "export AWS_CA_BUNDLE=\"/etc/ssl/certs/ca-bundle.crt\"" >> ~/kivera/setenv.sh
echo "export REQUESTS_CA_BUNDLE=\"/etc/ssl/certs/ca-bundle.crt\"" >> ~/kivera/setenv.sh
source ~/kivera/setenv.sh

# Sync time first to avoid SSL certificate validation issues
systemctl start chronyd 2>/dev/null || true
sleep 3

dnf update -y
dnf install -y jq pcre2-devel python3.11 python3.11-pip gcc python3.11-devel tzdata unzip bash htop amazon-cloudwatch-agent

# Create symlinks to use python3.11 as default
alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.11 1

# Install awscli for Python 3.11 (needed before S3 operations)
pip3 install awscli

export PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "PRIVATE_IP=$PRIVATE_IP" >> /etc/environment

source ~/.bashrc

mkdir -p ~/.ssh
echo 'Host *' > ~/.ssh/config
echo 'StrictHostKeyChecking no' >> ~/.ssh/config

cat <<EOF >> /opt/aws/amazon-cloudwatch-agent/etc/config.json
${cw_config}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

mkdir -p /locust
aws s3 cp s3://${s3_bucket}${s3_bucket_key}${deployment_id}/tests.zip ./tests.zip
unzip ./tests.zip -d /locust

cd /locust

[[ -e requirements.txt ]] && pip3 install --ignore-installed -r requirements.txt

export USER_WAIT_MIN=${user_wait_min}
export USER_WAIT_MAX=${user_wait_max}
export TEST_TIMEOUT=${test_timeout}
export LOCUST_USER_CLASSES=${locust_user_classes}

fallocate -l 50M test.data

export S3_TEST_BUCKET=${s3_bucket}
export S3_TEST_PATH=${s3_bucket_key}${deployment_id}

nohup locust \
    -f test.py \
    --worker \
    --master-host=${leader_ip} > locust-worker.out 2>&1 &
