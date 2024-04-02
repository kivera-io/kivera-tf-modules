#!/bin/bash

## tune box
echo "* hard nofile 100000" >> /etc/security/limits.conf
echo "* soft nofile 100000" >> /etc/security/limits.conf
echo "net.core.somaxconn=16384" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog=1000" >> /etc/sysctl.conf
sysctl -p

yum update -y
yum install -y jq pcre2-devel.x86_64 python3 pip3 gcc python3-devel tzdata curl unzip bash htop amazon-cloudwatch-agent -y

# LOCUST
export LOCUST_VERSION="2.16.0"
pip3 install locust==$LOCUST_VERSION

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

[[ -e requirements.txt ]] && pip3 install -r requirements.txt

mkdir -p ~/kivera

if [[ ${proxy_transparent_enabled} == false ]]; then
    time=180
    echo Polling http://${proxy_host}:8090/version
    while ! curl -s http://${proxy_host}:8090/version; do
        [[ $time == 0 ]] && echo "Failed to get response" && exit 1
        ((time-=1)); sleep 1;
    done

    curl -s http://${proxy_host}:8090/pub.cert > ~/kivera/ca-cert.pem
else
    echo ${proxy_pub_cert} > ~/kivera/ca-cert.pem
fi

cp ~/kivera/ca-cert.pem /etc/pki/ca-trust/source/anchors/ca-cert.pem
update-ca-trust extract

echo "
export AWS_CA_BUNDLE=\"~/kivera/ca-cert.pem\"
" > ~/kivera/setenv.sh
if [[ ${proxy_transparent_enabled} == false ]]; then
echo "
export HTTPS_PROXY=\"http://${proxy_host}:8080\"
export HTTP_PROXY=\"http://${proxy_host}:8080\"
export https_proxy=\"http://${proxy_host}:8080\"
export http_proxy=\"http://${proxy_host}:8080\"
export NO_PROXY=\"${leader_ip},${proxy_host},169.254.169.254,.github.com\"
export no_proxy=\"\$NO_PROXY\"
" >> ~/kivera/setenv.sh
fi

source ~/kivera/setenv.sh

export USER_WAIT_MIN=${user_wait_min}
export USER_WAIT_MAX=${user_wait_max}

fallocate -l 50M test.data

export S3_TEST_BUCKET=${s3_bucket}
export S3_TEST_PATH=${s3_bucket_key}${deployment_id}

nohup locust \
    -f test.py \
    --worker \
    --master-host=${leader_ip} > locust-worker.out 2>&1 &
