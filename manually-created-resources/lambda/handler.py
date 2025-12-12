import boto3
import json

# Initialize EC2 client outside the handler for performance
ec2 = boto3.client("ec2")

def lambda_handler(event, context):
    """
    Lambda function that reboots an EC2 instance when triggered
    by a CloudWatch alarm or EventBridge rule.

    The function expects the event payload to contain:
    event["detail"]["instance-id"]
    """

    print("Incoming event:", json.dumps(event, indent=2))

    # -----------------------------------------
    # 1. Extract instance ID from event payload
    # -----------------------------------------
    instance_id = None

    try:
        instance_id = event["detail"]["instance-id"]
    except KeyError:
        print("❌ Instance ID not found in the event structure.")
        return {
            "status": "failed",
            "reason": "Missing instance-id in event payload"
        }

    print(f"➡️ Trigger received for instance: {instance_id}")

    # -----------------------------------------
    # 2. Attempt to reboot the instance
    # -----------------------------------------
    try:
        response = ec2.reboot_instances(InstanceIds=[instance_id])
        print("Reboot API Response:", response)

        return {
            "status": "success",
            "action": "reboot",
            "instance_id": instance_id
        }

    except Exception as e:
        print(f"❌ Error rebooting EC2 instance {instance_id}: {e}")
        return {
            "status": "failed",
            "instance_id": instance_id,
            "error": str(e)
        }
