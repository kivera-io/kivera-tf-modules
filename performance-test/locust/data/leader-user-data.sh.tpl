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

if [[ ${leader_use_proxy} == true ]]; then
    if [[ ${proxy_transparent_enabled} == true ]]; then
        echo "${proxy_public_cert}" > ~/kivera/ca-cert.pem
    else
        time=180
        echo Polling http://${proxy_endpoint}:8090/version
        while ! curl -s http://${proxy_endpoint}:8090/version; do
            [[ $time == 0 ]] && echo "Failed to get response" && exit 1
            ((time-=1)); sleep 1;
        done

        echo "${proxy_public_cert}" > ~/kivera/ca-cert.pem

        echo "
        export HTTPS_PROXY=\"${proxy_protocol}://${proxy_endpoint}:8080\"
        export HTTP_PROXY=\"${proxy_protocol}://${proxy_endpoint}:8080\"
        export https_proxy=\"${proxy_protocol}://${proxy_endpoint}:8080\"
        export http_proxy=\"${proxy_protocol}://${proxy_endpoint}:8080\"
        export NO_PROXY=\"localhost,169.254.169.254,.github.com\"
        export no_proxy=\"\$NO_PROXY\"
        " >> ~/kivera/setenv.sh
    fi

    cp ~/kivera/ca-cert.pem /etc/pki/ca-trust/source/anchors/ca-cert.pem
    update-ca-trust extract

    echo "
    export AWS_CA_BUNDLE=\"/etc/ssl/certs/ca-bundle.crt\"
    export REQUESTS_CA_BUNDLE=\"/etc/ssl/certs/ca-bundle.crt\"
    " >> ~/kivera/setenv.sh

    source ~/kivera/setenv.sh
fi

dnf update -y
dnf install -y jq pcre2-devel gcc tzdata unzip htop amazon-cloudwatch-agent python3.11 python3.11-pip

cat <<EOF >> /opt/aws/amazon-cloudwatch-agent/etc/config.json
${cw_config}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

mkdir -p /locust
aws s3 cp s3://${s3_bucket}${s3_bucket_key}${deployment_id}/tests.zip ./tests.zip
unzip ./tests.zip -d /locust

cd /locust

[[ -f requirements.txt ]] && python3.11 -m pip install -r requirements.txt

if [[ ${leader_use_proxy} == false && ${proxy_transparent_enabled} == false ]]; then
    time=180
    echo Polling http://${proxy_endpoint}:8090/version
    while ! curl -s http://${proxy_endpoint}:8090/version; do
        [[ $time == 0 ]] && echo "Failed to get response" && exit 1
        ((time-=1)); sleep 1;
    done
fi

export USER_WAIT_MIN=${user_wait_min}
export USER_WAIT_MAX=${user_wait_max}
export LOCUST_USER_CLASSES=${locust_user_classes}
export LOCUST_WEB_USERNAME=${leader_username}
export LOCUST_WEB_PASSWORD=${leader_password}
export LOCUST_WEB_SECRET_KEY=${leader_secret_key}

nohup locust \
    -f test.py \
    --autostart \
    --web-port=80 \
    --web-login \
    --users=${locust_max_users} \
    --spawn-rate=${locust_spawn_rate} \
    --run-time=${locust_run_time}m \
    --expect-workers=${nodes_count} \
    --expect-workers-max-wait 500 \
    --master > locust-leader.out 2>&1 &
