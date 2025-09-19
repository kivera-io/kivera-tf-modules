#!/bin/bash -x
STATE=0

if [[ ${upstream_proxy} == true ]]; then
  # curl -s http://${upstream_proxy_endpoint}:8090/pub.cert > ~/public.pem
  # cp ~/public.pem /etc/pki/ca-trust/source/anchors/ca-cert.pem
  echo '${proxy_public_cert}' > /etc/pki/ca-trust/source/anchors/ca-cert.pem
  update-ca-trust extract
fi

if [[ "${upstream_proxy_endpoint}" != "" ]]; then
  export HTTPS_PROXY="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
  export HTTP_PROXY="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
  export https_proxy="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
  export http_proxy="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
  export no_proxy=169.254.169.254
  export NO_PROXY=169.254.169.254

  sed -i -e 's#http://#https://#g' /etc/yum.repos.d/td.repo
  echo "proxy=http://${upstream_proxy_endpoint}:${upstream_proxy_port}" >> /etc/yum.conf
fi

## tune box
echo "* hard nofile 100000" >> /etc/security/limits.conf
echo "* soft nofile 100000" >> /etc/security/limits.conf
echo "net.core.somaxconn=16384" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog=1000" >> /etc/sysctl.conf
sysctl -p

export KIVERA_DIR=/opt/kivera
export KIVERA_BIN_PATH=$KIVERA_DIR/bin
export KIVERA_CREDENTIALS=$KIVERA_DIR/etc/credentials.json
export KIVERA_CA_CERT=$KIVERA_DIR/etc/ca-cert.pem
export KIVERA_CA=$KIVERA_DIR/etc/ca.pem
export KIVERA_CERT_TYPE=${proxy_cert_type}
export KIVERA_LOGS_FILE=$KIVERA_DIR/var/log/proxy.log

mkdir -p $KIVERA_BIN_PATH $KIVERA_DIR/etc/ $KIVERA_DIR/var/log/

echo '${proxy_public_cert}' > $KIVERA_CA_CERT

if [[ '${proxy_private_key_secret_arn}' != "" ]]; then
  export KIVERA_CA_SECRET_REGION=$(echo ${proxy_private_key_secret_arn} | cut -d':' -f4)
  aws secretsmanager get-secret-value --secret-id '${proxy_private_key_secret_arn}' --region $KIVERA_CA_SECRET_REGION --query SecretString --output text > $KIVERA_CA
fi

export KIVERA_CREDENTIALS_SECRET_REGION=$(echo ${proxy_credentials_secret_arn} | cut -d':' -f4)
aws secretsmanager get-secret-value --secret-id '${proxy_credentials_secret_arn}' --region $KIVERA_CREDENTIALS_SECRET_REGION --query SecretString --output text > $KIVERA_CREDENTIALS

export REDIS_CONNECTION_STRING_SECRET_REGION=$(echo ${redis_connection_string_arn} | cut -d':' -f4)

cat << EOF > $KIVERA_DIR/etc/env.txt
KIVERA_CREDENTIALS=$KIVERA_CREDENTIALS
KIVERA_TRACING_ENABLED=${enable_datadog_tracing}
KIVERA_PROFILING_ENABLED=${enable_datadog_profiling}
DD_TRACE_SAMPLE_RATE=${datadog_trace_sampling_rate}
EOF

if [[ ${external_ca} == true ]]; then
cat << EOF >> $KIVERA_DIR/etc/env.txt
KIVERA_EXTERNAL_CA=true
KIVERA_AWS_PCA_ARN=${pca_arn}
EOF
else
cat << EOF >> $KIVERA_DIR/etc/env.txt
KIVERA_CA=$KIVERA_CA
KIVERA_CA_CERT=$KIVERA_CA_CERT
KIVERA_CERT_TYPE=$KIVERA_CERT_TYPE
EOF
fi

if [[ ${cache_enabled} == true && ${cache_iam_auth} == false ]]; then
cat << EOF >> $KIVERA_DIR/etc/env.txt
KIVERA_KV_STORE_CONNECT=$(aws secretsmanager get-secret-value --secret-id '${redis_connection_string_arn}' --region $REDIS_CONNECTION_STRING_SECRET_REGION --query SecretString --output text)
KIVERA_KV_STORE_CLUSTER_MODE=true
EOF
elif [[ ${cache_enabled} == true && ${cache_iam_auth} == true ]]; then
cat << EOF >> $KIVERA_DIR/etc/env.txt
KIVERA_KV_STORE_CONNECT=${redis_iam_connection_string}
KIVERA_KV_STORE_CLUSTER_MODE=true
KIVERA_KV_STORE_AUTH_TYPE=iam
KIVERA_KV_STORE_IAM_CLUSTER_NAME=${cache_cluster_name}
KIVERA_KV_STORE_IAM_REGION=${region}
EOF
fi

if [[ "${upstream_proxy_endpoint}" != "" ]]; then
cat << EOF >> $KIVERA_DIR/etc/env.txt
HTTPS_PROXY="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
HTTP_PROXY="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
https_proxy="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
http_proxy="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
no_proxy=169.254.169.254
NO_PROXY=169.254.169.254
EOF
fi

if [[ ${proxy_https} == true ]]; then
aws secretsmanager get-secret-value --secret-id '${proxy_https_key_arn}' --region $KIVERA_CREDENTIALS_SECRET_REGION --query SecretString --output text > $KIVERA_DIR/etc/https_key.pem
echo '${proxy_https_cert}' > $KIVERA_DIR/etc/https_cert.pem
cat << EOF >> $KIVERA_DIR/etc/env.txt
KIVERA_HTTPS_PORT=8080
KIVERA_HTTPS_PRIVATE_KEY=$KIVERA_DIR/etc/https_key.pem
KIVERA_HTTPS_PUBLIC_CERT=$KIVERA_DIR/etc/https_cert.pem
EOF
fi

groupadd -r kivera
useradd -mrg kivera kivera
useradd -g kivera td-agent

if [[ "${proxy_s3_path}" != "" ]]; then
    aws s3 cp ${proxy_s3_path} ./proxy.zip
    unzip ./proxy.zip -d $KIVERA_BIN_PATH
else
    wget https://download.kivera.io/binaries/proxy/linux/amd64/kivera-${proxy_version}.tar.gz -O proxy.tar.gz
    tar -xvzf proxy.tar.gz -C $KIVERA_DIR
    cp $KIVERA_BIN_PATH/linux/amd64/kivera $KIVERA_BIN_PATH/kivera
fi
chmod 0755 $KIVERA_BIN_PATH/kivera
chown -R kivera:kivera $KIVERA_DIR

yum install amazon-cloudwatch-agent -y

if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  DD_API_KEY=`aws secretsmanager get-secret-value --query SecretString --output text --region ap-southeast-2 --secret-id ${datadog_secret_arn}`
  export DD_API_KEY
  DD_SITE="datadoghq.com" DD_APM_INSTRUMENTATION_ENABLED=host bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
  
  if [[ "${upstream_proxy_endpoint}" != "" ]]; then
    cat << EOF >> /etc/datadog-agent/environment
      DD_PROXY_HTTPS="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
      DD_PROXY_HTTP="http://${upstream_proxy_endpoint}:${upstream_proxy_port}"
EOF
  fi
fi


# add GPG key
rpm --import https://packages.treasuredata.com/GPG-KEY-td-agent

# add treasure data repository to yum
cat >/etc/yum.repos.d/td.repo <<'EOF';
[treasuredata]
name=TreasureData
baseurl=http://packages.treasuredata.com/4/amazon/2/\$basearch
gpgcheck=1
gpgkey=https://packages.treasuredata.com/GPG-KEY-td-agent
EOF

# update your sources
yum check-update

# install the toolbelt
yum install -y td-agent
# curl -L https://toolbelt.treasuredata.com/sh/install-amazon2-td-agent4.sh | sh
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
EnvironmentFile=$KIVERA_DIR/etc/env.txt

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

# Enable CloudWatch logging/metrics
cat << EOF | tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 5
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
      ["InstanceName"],
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
        ],
        "metrics_collection_interval": 5,
        "append_dimensions": {
          "InstanceName": "${instance_name}"
        }
      }
    }
  }
}
EOF

# Enable services
if [[ ${proxy_log_to_kivera} == true ]]; then
  systemctl enable td-agent.service
  systemctl restart td-agent.service
fi
if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  systemctl enable datadog-agent
  systemctl restart datadog-agent
fi
systemctl enable amazon-cloudwatch-agent.service
systemctl restart amazon-cloudwatch-agent.service
systemctl enable kivera.service
systemctl restart kivera.service

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
