"""
DELETE /tasks/{taskId}
Soft-deletes a task by setting status=cancelled and TTL=7 days.
Hard deletion handled by DynamoDB TTL automatically.
"""
import json
import os
from datetime import datetime, timezone, timedelta
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

TTL_DAYS = 7  # Deleted tasks expire from DynamoDB after 7 days


def lambda_handler(event, context):
    task_id = (event.get("pathParameters") or {}).get("taskId", "").strip()
    if not task_id:
        return _response(400, {"error": "taskId path parameter is required"})

    now = datetime.now(timezone.utc)
    expiry = int((now + timedelta(days=TTL_DAYS)).timestamp())

    try:
        table.update_item(
            Key={"taskId": task_id},
            UpdateExpression="SET #s = :cancelled, updatedAt = :now, deletedAt = :now, #ttl = :expiry",
            ExpressionAttributeNames={"#s": "status", "#ttl": "ttl"},
            ExpressionAttributeValues={
                ":cancelled": "cancelled",
                ":now": now.isoformat(),
                ":expiry": expiry,
            },
            ConditionExpression="attribute_exists(taskId) AND #s <> :cancelled",
        )
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "ConditionalCheckFailedException":
            return _response(404, {"error": f"Task {task_id!r} not found or already cancelled"})
        raise

    return _response(200, {
        "message": f"Task {task_id} cancelled. Will be permanently deleted in {TTL_DAYS} days.",
        "taskId": task_id,
    })


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
