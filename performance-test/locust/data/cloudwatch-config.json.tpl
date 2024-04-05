{
    "agent": {
        "metrics_collection_interval": 5,
        "run_as_user": "root"
    },
    "metrics": {
        "aggregation_dimensions": [
            [ "InstanceId" ],
            [ "InstanceName" ]
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
            },
            "mem": {
                "measurement": [
                    "mem_used",
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 5,
                "append_dimensions": {
                    "InstanceName": "${instance_name}"
                }
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 5,
                "append_dimensions": {
                    "InstanceName": "${instance_name}"
                }
            },
            "net": {
                "measurement": [
                    "net_bytes_recv",
                    "net_bytes_sent",
                    "net_packets_recv",
                    "net_packets_sent",
                    "net_drop_in",
                    "net_drop_out"
                ],
                "metrics_collection_interval": 5,
                "append_dimensions": {
                    "InstanceName": "${instance_name}"
                }
            }
        }
    }
}