"""
GET /tasks/{taskId}
Retrieves a single task from DynamoDB.
"""
import json
import os
import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    task_id = (event.get("pathParameters") or {}).get("taskId", "").strip()

    if not task_id:
        return _response(400, {"error": "taskId path parameter is required"})

    try:
        result = table.get_item(Key={"taskId": task_id})
    except ClientError as e:
        return _response(500, {"error": "Database error", "detail": str(e)})

    item = result.get("Item")
    if not item:
        return _response(404, {"error": f"Task {task_id!r} not found"})

    return _response(200, item)


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
