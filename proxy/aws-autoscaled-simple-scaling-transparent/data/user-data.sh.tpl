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
git checkout transparent-tuning
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

if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  DD_API_KEY=`aws secretsmanager get-secret-value --query SecretString --output text --region ap-southeast-2 --secret-id ${ddog_secret_arn}`
  export DD_API_KEY
  DD_SITE="datadoghq.com" DD_APM_INSTRUMENTATION_ENABLED=host bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
fi

# Enable services
if [[ ${enable_datadog_tracing} == true || ${enable_datadog_profiling} == true ]]; then
  systemctl enable datadog-agent
  systemctl start datadog-agent
fi
