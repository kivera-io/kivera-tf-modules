#!/usr/bin/bash

# Note: This requires this instance to have Source/Dest check disabled; we need to assign a role to the ec2 instance to enable and disable it


echo "Running tunnel handler script... "
echo Mode is $1, In Int is $2, Out Int is $3, ENI is $4

iptables -F
iptables -t nat -F
INSTANCE_ID=$(curl 169.254.169.254/latest/meta-data/instance-id)

case $1 in
        CREATE)

                iptables -P INPUT ACCEPT
                iptables -P FORWARD ACCEPT
                iptables -P OUTPUT ACCEPT

                iptables -t nat -F
                iptables -t mangle -F
                iptables -F
                iptables -X

                echo "Removing IP FORWARD"
                echo 0 > /proc/sys/net/ipv4/ip_forward
                echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter
                echo 1 > /proc/sys/net/ipv4/conf/$2/rp_filter

                curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document > /home/ec2-user/iid;
                export instance_id=$(cat /home/ec2-user/iid | jq -r .instanceId);
                export instance_ip=$(cat /home/ec2-user/iid | jq -r .privateIp);
                echo "Setting up NAT and IP FORWARD"
                iptables -t nat -A PREROUTING -p tcp -m tcp ! -d $instance_ip --dport 443 -j DNAT --to-destination $instance_ip:10080
                iptables -t nat -A PREROUTING -p tcp -m tcp ! -d $instance_ip --dport 443 -j REDIRECT --to-ports 10080
                iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
                iptables -A FORWARD -i $2 -o $2 -j ACCEPT

                echo 1 > /proc/sys/net/ipv4/ip_forward
                echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
                echo 0 > /proc/sys/net/ipv4/conf/$2/rp_filter
                ;;

        DESTROY)

                iptables -P INPUT ACCEPT
                iptables -P FORWARD ACCEPT
                iptables -P OUTPUT ACCEPT

                iptables -t nat -F
                iptables -t mangle -F
                iptables -F
                iptables -X

                echo "Removing IP FORWARD"
                echo 0 > /proc/sys/net/ipv4/ip_forward
                echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter
                echo 1 > /proc/sys/net/ipv4/conf/$2/rp_filter
                ;;
        *)
                echo "invalid action."
                exit 1
                ;;
esac