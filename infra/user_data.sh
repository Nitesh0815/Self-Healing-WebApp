#!/bin/bash
# Log everything for debugging
exec > /var/log/user_data.log 2>&1
echo "===== Starting Self-Healing App Setup ====="

#############################################
# 1. Update system
#############################################
yum update -y

#############################################
# 2. Install Apache (Web Server)
#############################################
yum install -y httpd

systemctl enable httpd
systemctl start httpd

#############################################
# 3. Install CloudWatch Agent
#############################################
yum install -y amazon-cloudwatch-agent

#######################################################
# 4. Create CloudWatch Agent config file
#######################################################
cat <<EOF >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "metrics": {
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_guest", "rename": "GuestCPU", "unit": "Percent"},
          {"name": "cpu_usage_idle", "rename": "IdleCPU", "unit": "Percent"},
          {"name": "cpu_usage_system", "rename": "SystemCPU", "unit": "Percent"},
          {"name": "cpu_usage_user", "rename": "UserCPU", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent", "inodes_free"
        ],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "selfheal-app-system-logs",
            "log_stream_name": "{instance_id}-messages",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/httpd/error_log",
            "log_group_name": "selfheal-app-httpd-errors",
            "log_stream_name": "{instance_id}-httpd-error"
          },
          {
            "file_path": "/var/log/user_data.log",
            "log_group_name": "selfheal-app-userdata",
            "log_stream_name": "{instance_id}-userdata"
          }
        ]
      }
    }
  }
}
EOF

#######################################################
# 5. Start CloudWatch Agent
#######################################################
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

echo "CloudWatch Agent Started"

#######################################################
# 6. Deploy Web App Page
#######################################################
cat <<EOF >/var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
  <title>Self-Healing WebApp</title>
</head>
<body style="font-family: Arial; text-align:center; margin-top:50px;">
  <h1 style="color:green;">Welcome to the Self-Healing WebApp</h1>
  <h3>This instance is healthy and monitored.</h3>
  <p><b>Instance ID:</b> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
  <p><b>AZ:</b> $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
</body>
</html>
EOF

chown apache:apache /var/www/html/index.html

#######################################################
# 7. Ensure Apache auto-restarts if crashed
#######################################################
systemctl enable httpd
systemctl restart httpd

echo "===== User Data Execution Completed Successfully ====="
