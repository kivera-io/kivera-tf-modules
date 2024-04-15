#!/usr/bin/bash

# Note: This requires this instance to have Source/Dest check disabled; we need to assign a role to the ec2 instance to enable and disable it


echo "Running tunnel handler script... "
echo Mode is $1, In Int is $2, Out Int is $3, ENI is $4

iptables -F
iptables -t nat -F
INSTANCE_ID=$(curl 169.254.169.254/latest/meta-data/instance-id)

case $1 in
        CREATE)

                echo "==> Setting up simple passthrough"
                echo Mode is $1, In Int is $2, Out Int is $3, ENI is $4
                tc qdisc add dev $2 ingress
                tc filter add dev $2 parent ffff: protocol all prio 2 u32 match u32 0 0 flowid 1:1 action mirred egress mirror dev $3
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