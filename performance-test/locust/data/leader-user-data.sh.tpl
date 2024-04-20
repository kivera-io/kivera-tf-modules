#!/bin/bash
set -x

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

sleep 60

if [[ ${proxy_transparent_enabled} == false ]]; then
    time=180
    echo Polling http://${proxy_host}:8090/version
    while ! curl -s http://${proxy_host}:8090/version; do
        [[ $time == 0 ]] && echo "Failed to get response" && exit 1
        ((time-=1)); sleep 1;
    done
fi

export USER_WAIT_MIN=${user_wait_min}
export USER_WAIT_MAX=${user_wait_max}

test_file=$([[ ${proxy_transparent_enabled} == true ]] && echo "test_transparent.py" || echo "test.py")

nohup locust \
    -f $test_file \
    --autostart \
    --web-port=80 \
    --web-auth ${leader_username}:${leader_password} \
    --users=${locust_max_users} \
    --spawn-rate=${locust_spawn_rate} \
    --run-time=${locust_run_time} \
    --expect-workers=${nodes_count} \
    --expect-workers-max-wait 300 \
    --master > locust-leader.out 2>&1 &
