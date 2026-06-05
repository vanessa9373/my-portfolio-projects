"""
POST /tasks
Creates a new task in DynamoDB.
"""
import json
import os
import uuid
from datetime import datetime, timezone
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    title = (body.get("title") or "").strip()
    if not title:
        return _response(400, {"error": "title is required"})

    if len(title) > 200:
        return _response(400, {"error": "title must be 200 characters or fewer"})

    task_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    item = {
        "taskId":      task_id,
        "title":       title,
        "description": (body.get("description") or "").strip(),
        "status":      "pending",
        "priority":    body.get("priority", "medium"),
        "createdAt":   now,
        "updatedAt":   now,
        "ttl":         None,  # Optional: set expiry via caller
    }

    # Remove None values — DynamoDB rejects them
    item = {k: v for k, v in item.items() if v is not None}

    try:
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(taskId)",  # Safety: never overwrite
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(409, {"error": "Task ID collision — retry"})
        raise

    return _response(201, item)


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
