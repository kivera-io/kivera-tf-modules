#!/bin/bash -x
STATE=0

if [[ ${upstream_proxy} == true ]]; then
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

  echo "proxy=http://${upstream_proxy_endpoint}:${upstream_proxy_port}" >> /etc/dnf/dnf.conf
fi

## tune box
echo "* hard nofile 100000" >> /etc/security/limits.conf
echo "* soft nofile 100000" >> /etc/security/limits.conf
echo "net.core.somaxconn=16384" >> /etc/sysctl.conf
echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
echo "net.core.netdev_max_backlog=1000" >> /etc/sysctl.conf
sysctl -p

export PROXY_DIR=/opt/koxy
export PROXY_CA_CERT=$PROXY_DIR/ca-cert.pem
export PROXY_CA_KEY=$PROXY_DIR/ca-key.pem
export PROXY_CONFIG=$PROXY_DIR/config.yaml
export PROXY_LOGS_FILE=$PROXY_DIR/var/log/proxy.log

mkdir -p $PROXY_DIR/var/log

echo '${proxy_public_cert}' > $PROXY_CA_CERT

if [[ '${proxy_private_key_secret_arn}' != "" ]]; then
  export PROXY_CA_SECRET_REGION=$(echo ${proxy_private_key_secret_arn} | cut -d':' -f4)
  aws secretsmanager get-secret-value --secret-id '${proxy_private_key_secret_arn}' --region $PROXY_CA_SECRET_REGION --query SecretString --output text > $PROXY_CA_KEY
fi

# Write proxy config file
cat << 'PROXYCFG' > $PROXY_CONFIG
---
telemetry:
  tracing:
    enabled: false
  logging:
    format: json
    verbosity: INFO
runtime:
  enable_seccomp: false
app:
  cloudflare:
    url: https://pastebin.com/raw/Q3Rw4sZJ
    poll_interval_secs: 10
  socks5_addr: "0.0.0.0:1080"
endpoints:
  HTTP Proxy:
    listener:
      http_1_and_2:
        addr:
          socket_addr:
            - "0.0.0.0:8080"
    tunnel:
      tls_interception:
        enabled: true
        ca_cert: ./cac-proxy/cfg/ca/ca-cert.pem
        ca_private_key: ./cac-proxy/cfg/ca/ca-key.pem
PROXYCFG

dnf install amazon-cloudwatch-agent unzip -y

groupadd -r koxy
useradd -Mrg koxy koxy

aws s3 cp ${proxy_s3_path} ./proxy.zip
unzip ./proxy.zip -d $PROXY_DIR
chmod 0755 $PROXY_DIR/koxy
chown -R koxy:koxy $PROXY_DIR

if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  DD_SECRET_REGION=$(echo ${datadog_secret_arn} | cut -d':' -f4)
  DD_API_KEY=`aws secretsmanager get-secret-value --query SecretString --output text --region $DD_SECRET_REGION --secret-id ${datadog_secret_arn}`
  export DD_API_KEY
  DD_SITE="datadoghq.com" DD_APM_INSTRUMENTATION_ENABLED=host bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"

  if [[ "${upstream_proxy_endpoint}" != "" ]]; then
    cat << EOF >> /etc/datadog-agent/environment
DD_PROXY_HTTPS=http://${upstream_proxy_endpoint}:${upstream_proxy_port}
DD_PROXY_HTTP=http://${upstream_proxy_endpoint}:${upstream_proxy_port}
EOF
  fi
fi

# Configure koxy service
cat << EOF | tee /etc/systemd/system/koxy.service
[Unit]
Description=Koxy Proxy

[Service]
User=koxy
WorkingDirectory=$PROXY_DIR
ExecStart=/usr/bin/sh -c "$PROXY_DIR/koxy --config $PROXY_CONFIG | tee -a $PROXY_LOGS_FILE"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Configure log file rotation
cat << EOF | tee /etc/systemd/system/koxy-logrotate.service
[Unit]
Description=Koxy log rotation

[Service]
Type=oneshot
ExecStart=/usr/sbin/logrotate -s /var/lib/logrotate/klogrotate.status /etc/klogrotate.conf
EOF

cat << EOF | tee /etc/systemd/system/koxy-logrotate.timer
[Unit]
Description=Hourly koxy log rotation

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat << EOF | tee /etc/klogrotate.conf
$PROXY_LOGS_FILE {
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
            "file_path": "$PROXY_LOGS_FILE",
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
systemctl daemon-reload
if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  systemctl enable datadog-agent
  systemctl restart datadog-agent
fi
systemctl enable amazon-cloudwatch-agent.service
systemctl restart amazon-cloudwatch-agent.service
systemctl enable koxy.service
systemctl restart koxy.service
systemctl enable koxy-logrotate.timer
systemctl start koxy-logrotate.timer

sleep 10

CLOUDWATCH_PROCESS=$(systemctl is-active amazon-cloudwatch-agent.service)
  [[ $CLOUDWATCH_PROCESS == "active" ]] \
    && echo "CloudWatch agent service is running" \
    || (echo "CloudWatch agent service is not running" && STATE=1)

KOXY_PROCESS=$(systemctl is-active koxy.service)
[[ $KOXY_PROCESS == "active" ]] \
  && echo "The koxy service appears to be healthy." \
  || (echo "The koxy service appears unhealthy." && STATE=1)
