"""
PATCH /tasks/{taskId}
Updates mutable fields on a task. Uses optimistic locking via updatedAt.
"""
import json
import os
from datetime import datetime, timezone
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

VALID_STATUSES = {"pending", "in_progress", "completed", "cancelled"}
VALID_PRIORITIES = {"low", "medium", "high", "critical"}
MUTABLE_FIELDS = {"title", "description", "status", "priority"}


def lambda_handler(event, context):
    task_id = (event.get("pathParameters") or {}).get("taskId", "").strip()
    if not task_id:
        return _response(400, {"error": "taskId path parameter is required"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    updates = {k: v for k, v in body.items() if k in MUTABLE_FIELDS}
    if not updates:
        return _response(400, {"error": f"At least one of {MUTABLE_FIELDS} must be provided"})

    # Validate specific fields
    if "status" in updates and updates["status"] not in VALID_STATUSES:
        return _response(400, {"error": f"status must be one of: {', '.join(VALID_STATUSES)}"})

    if "priority" in updates and updates["priority"] not in VALID_PRIORITIES:
        return _response(400, {"error": f"priority must be one of: {', '.join(VALID_PRIORITIES)}"})

    now = datetime.now(timezone.utc).isoformat()
    updates["updatedAt"] = now

    # Build UpdateExpression dynamically
    set_expressions = []
    expression_values = {}
    expression_names = {}

    for key, val in updates.items():
        placeholder = f":v_{key}"
        name_placeholder = f"#n_{key}"
        set_expressions.append(f"{name_placeholder} = {placeholder}")
        expression_values[placeholder] = val
        expression_names[name_placeholder] = key

    update_expr = "SET " + ", ".join(set_expressions)

    try:
        result = table.update_item(
            Key={"taskId": task_id},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expression_values,
            ExpressionAttributeNames=expression_names,
            ConditionExpression="attribute_exists(taskId)",  # Ensure task exists
            ReturnValues="ALL_NEW",
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(404, {"error": f"Task {task_id!r} not found"})
        raise

    return _response(200, result["Attributes"])


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
