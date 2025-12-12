import boto3
import json

# Create EC2 client
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Lambda function to reboot EC2 instances when CloudWatch alarm triggers.
    Event contains the instance ID from CloudWatch.
    """
    print("Received event:", json.dumps(event))

    # Extract the instance ID from the event
    try:
        instance_id = event['detail']['instance-id']
    except KeyError:
        # Sometimes the event might come differently
        print("No instance ID found in event. Exiting.")
        return {"status": "failed", "reason": "No instance ID in event"}

    print(f"Rebooting instance: {instance_id}")

    # Reboot the EC2 instance
    try:
        response = ec2.reboot_instances(InstanceIds=[instance_id])
        print("Reboot response:", response)
        return {"status": "success", "instance": instance_id}
    except Exception as e:
        print("Error rebooting instance:", e)
        return {"status": "failed", "instance": instance_id, "error": str(e)}
