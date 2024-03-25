#!/bin/bash -x
STATE=0

## tune box
echo "* hard nofile 100000" >> /etc/security/limits.conf
echo "* soft nofile 100000" >> /etc/security/limits.conf
echo "net.core.somaxconn=16384" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog=1000" >> /etc/sysctl.conf
sysctl -p

export KIVERA_BIN_PATH=/opt/kivera/bin
export KIVERA_CREDENTIALS=/opt/kivera/etc/credentials.json
export KIVERA_CA_CERT=/opt/kivera/etc/ca-cert.pem
export KIVERA_CA=/opt/kivera/etc/ca.pem
export KIVERA_CERT_TYPE=${proxy_cert_type}
export KIVERA_LOGS_FILE=/opt/kivera/var/log/proxy.log
export KIVERA_REDIS_ADDR=${redis_connection_string}
export KIVERA_TRANS_MODE=true

## diable source/dest check
INSTANCE_ID=$(curl 169.254.169.254/latest/meta-data/instance-id)
INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
aws ec2 modify-instance-attribute --no-source-dest-check --instance-id $INSTANCE_ID --region $INSTANCE_REGION

## install dependencies
amazon-linux-extras install epel
yum install -y supervisor cmake3 amazon-cloudwatch-agent jq
yum groupinstall -y "Development Tools"

systemctl enable supervisord

## install gwlbtun.service @ boot
aws s3 cp ${tunneler_file} /tmp/tunnel-handler.sh
git clone https://github.com/kivera-io/aws-gateway-load-balancer-tunnel-handler.git /opt/aws-gateway-load-balancer-tunnel-handler
cd /opt/aws-gateway-load-balancer-tunnel-handler
cp /tmp/tunnel-handler.sh /opt/aws-gateway-load-balancer-tunnel-handler/
cmake3 .
make
cd -

## enable gwlbtun @ boot
aws s3 cp ${glb_file} /tmp/gwlbtun.service
cp /tmp/gwlbtun.service /usr/lib/systemd/system/
chmod +x /opt/aws-gateway-load-balancer-tunnel-handler/tunnel-handler.sh
systemctl daemon-reload
systemctl enable --no-block gwlbtun.service
systemctl restart gwlbtun.service
systemctl status gwlbtun.service

# log file
cat << EOF | tee /etc/cron.hourly/kivera-logrotate
#!/bin/sh
/usr/sbin/logrotate -s /var/lib/logrotate/klogrotate.status /etc/klogrotate.conf
EXITVALUE=\$?
if [ \$EXITVALUE != 0 ]; then
    /usr/bin/logger -t logrotate "ALERT exited abnormally with [\$EXITVALUE]"
fi
exit 0
EOF

cat << EOF | tee /etc/klogrotate.conf
$KIVERA_LOGS_FILE {
    maxsize 500M
    hourly
    missingok
    rotate 8
    compress
    notifempty
    copytruncate
}
EOF

mkdir -p $KIVERA_BIN_PATH /opt/kivera/etc/ /opt/kivera/var/log/

echo '${proxy_public_cert}' > $KIVERA_CA_CERT

export KIVERA_CA_SECRET_REGION=$(echo ${proxy_private_key_secret_arn} | cut -d':' -f4)
export KIVERA_CREDENTIALS_SECRET_REGION=$(echo ${proxy_credentials_secret_arn} | cut -d':' -f4)

aws secretsmanager get-secret-value --secret-id '${proxy_private_key_secret_arn}' --region $KIVERA_CA_SECRET_REGION --query SecretString --output text > $KIVERA_CA
aws secretsmanager get-secret-value --secret-id '${proxy_credentials_secret_arn}' --region $KIVERA_CREDENTIALS_SECRET_REGION --query SecretString --output text > $KIVERA_CREDENTIALS

groupadd -r kivera
useradd -mrg kivera kivera
useradd -g kivera td-agent

if [[ "${proxy_s3_path}" != "" ]]; then
    aws s3 cp ${proxy_s3_path} ./proxy.zip
    unzip ./proxy.zip -d $KIVERA_BIN_PATH
else
    wget https://download.kivera.io/binaries/proxy/linux/amd64/kivera-${proxy_version}.tar.gz -O proxy.tar.gz
    tar -xvzf proxy.tar.gz -C /opt/kivera
    cp $KIVERA_BIN_PATH/linux/amd64/kivera $KIVERA_BIN_PATH/kivera
fi
chmod 0755 $KIVERA_BIN_PATH/kivera
chown -R kivera:kivera /opt/kivera

yum install amazon-cloudwatch-agent -y

if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  DD_API_KEY=`aws secretsmanager get-secret-value --query SecretString --output text --region ap-southeast-2 --secret-id ${ddog_secret_arn}`
  export DD_API_KEY
  DD_SITE="datadoghq.com" DD_APM_INSTRUMENTATION_ENABLED=host bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
fi

curl -L https://toolbelt.treasuredata.com/sh/install-amazon2-td-agent4.sh | sh
td-agent-gem install -N fluent-plugin-out-kivera

# Configure Kivera service
cat << EOF | tee /etc/systemd/system/kivera.service
[Unit]
Description=Kivera Proxy

[Service]
User=kivera
WorkingDirectory=$KIVERA_BIN_PATH
ExecStart=/usr/bin/sh -c "$KIVERA_BIN_PATH/kivera | tee -a $KIVERA_LOGS_FILE"
Restart=always
Environment=KIVERA_CREDENTIALS=$KIVERA_CREDENTIALS
Environment=KIVERA_CA_CERT=$KIVERA_CA_CERT
Environment=KIVERA_CA=$KIVERA_CA
Environment=KIVERA_CERT_TYPE=$KIVERA_CERT_TYPE
Environment=KIVERA_KV_STORE_CONNECT=$KIVERA_REDIS_ADDR
Environment=KIVERA_KV_STORE_CLUSTER_MODE=true
Environment=KIVERA_TRACING_ENABLED=${enable_datadog_tracing}
Environment=KIVERA_PROFILING_ENABLED=${enable_datadog_profiling}
Environment=DD_TRACE_SAMPLE_RATE=${ddog_trace_sampling_rate}
Environment=KIVERA_TRANS_MODE=$KIVERA_TRANS_MODE

[Install]
WantedBy=multi-user.target
EOF

# Configure remote logging
mkdir -p /etc/systemd/system/td-agent.service.d/

cat << EOF | tee /etc/systemd/system/td-agent.service.d/override.conf
[Service]
Group=kivera
EOF

cat << EOF | tee /etc/td-agent/td-agent.conf
<source>
  @type tail
  tag kivera
  path $KIVERA_LOGS_FILE
  pos_file /var/log/td-agent/kivera.log.pos
  <parse>
    @type json
  </parse>
</source>
<match kivera>
  @type kivera
  config_file $KIVERA_CREDENTIALS
  bulk_request
  <buffer>
    flush_interval 1
    chunk_limit_size 1m
    flush_thread_interval 0.1
    flush_thread_burst_interval 0.01
    flush_thread_count 15
  </buffer>
</match>
EOF

# Configure log file rotation
cat << EOF | tee /etc/cron.hourly/kivera-logrotate
#!/bin/sh
/usr/sbin/logrotate -s /var/lib/logrotate/kivera.status /etc/kivera-logrotate.conf
EXITVALUE=\$?
if [ \$EXITVALUE != 0 ]; then
    /usr/bin/logger -t logrotate "ALERT exited abnormally with [\$EXITVALUE]"
fi
exit 0
EOF

cat << EOF | tee /etc/kivera-logrotate.conf
$KIVERA_LOGS_FILE {
    maxsize 500M
    hourly
    missingok
    rotate 8
    compress
    notifempty
    copytruncate
}
EOF

# Enable CloudWatch logging/metrics
cat << EOF | tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 1,
    "run_as_user": "cwagent"
  },
  $([[ ${proxy_log_to_cloudwatch} == true ]] && echo '"logs": {
    "log_stream_name": "{instance_id}",
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "$KIVERA_LOGS_FILE",
            "log_group_name": "${log_group_name}",
            "retention_in_days": ${log_group_retention_in_days}
          }
        ]
      }
    }
  },' | envsubst)
  "metrics": {
    "namespace": "kivera",
    "aggregation_dimensions": [
      ["InstanceId"],
      ["AutoScalingGroupName"]
    ],
    "append_dimensions": {
      "AutoScalingGroupName": "\$${aws:AutoScalingGroupName}",
      "ImageId": "\$${aws:ImageId}",
      "InstanceId": "\$${aws:InstanceId}",
      "InstanceType": "\$${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_active"
        ]
      }
    }
  }
}
EOF

# Update source/dest check
EC2_INSTANCE_ID="`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`"
EC2_REGION_ID="`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//'`"
aws ec2 modify-instance-attribute --no-source-dest-check --instance-id $EC2_INSTANCE_ID --region $EC2_REGION_ID

# Enable services
if [[ ${proxy_log_to_kivera} == true ]]; then
  systemctl enable td-agent.service
  systemctl start td-agent.service
fi
systemctl enable amazon-cloudwatch-agent.service
systemctl start amazon-cloudwatch-agent.service
systemctl enable kivera.service
systemctl start kivera.service
systemctl enable datadog-agent
systemctl start datadog-agent

sleep 10

if [[ ${proxy_log_to_kivera} == true ]]; then
FLUENTD_PROCESS=$(systemctl is-active td-agent.service)
  [[ $FLUENTD_PROCESS -eq "active" ]] \
    && echo "Fluentd service is running" \
    || (echo "Fluentd service is not running" && STATE=1)
fi

CLOUDWATCH_PROCESS=$(systemctl is-active amazon-cloudwatch-agent.service)
  [[ $CLOUDWATCH_PROCESS -eq "active" ]] \
    && echo "CloudWatch agent service is running" \
    || (echo "CloudWatch agent service is not running" && STATE=1)

KIVERA_PROCESS=$(systemctl is-active kivera.service)
KIVERA_CONNECTIONS=$(lsof -i -P -n | grep kivera)
[[ $KIVERA_PROCESS -eq "active" && $KIVERA_CONNECTIONS == *"(ESTABLISHED)"* && $KIVERA_CONNECTIONS == *"(LISTEN)"* ]] \
  && echo "The Kivera service and connections appears to be healthy." \
  || (echo "The Kivera service and connections appear unhealthy." && STATE=1)

