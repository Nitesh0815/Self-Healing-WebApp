#!/bin/bash
set -xe

exec > /var/log/user_data.log 2>&1

echo "[START] User data running"

#############################################
# Ensure correct folders exist
#############################################
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

#############################################
# Update system
#############################################
yum clean all
yum update -y || yum update -y

#############################################
# Install Apache
#############################################
yum install -y httpd
systemctl enable httpd
systemctl start httpd

#############################################
# Install CloudWatch Agent
#############################################
yum install -y amazon-cloudwatch-agent

#############################################
# Write CloudWatch config
#############################################
cat <<'EOF' >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          { "name": "cpu_usage_idle" },
          { "name": "cpu_usage_user" },
          { "name": "cpu_usage_system" }
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
EOF

#############################################
# Start CloudWatch Agent
#############################################
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

#############################################
# Deploy basic web page
#############################################
cat <<EOF >/var/www/html/index.html
<h1 style="color:green; text-align:center;">
  Self-Healing WebApp is Running
</h1>
<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
<p>AZ: $(curl -s http://169.254.169254/latest/meta-data/placement/availability-zone)</p>
EOF

chown apache:apache /var/www/html/index.html

#############################################
# Final restart to ensure Apache is active
#############################################
systemctl restart httpd

echo "[END] User data completed"
