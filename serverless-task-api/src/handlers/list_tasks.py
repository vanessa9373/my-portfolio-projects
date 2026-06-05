"""
GET /tasks?status=pending&limit=20&lastKey=xxx
Lists tasks from DynamoDB with optional status filter and pagination.
"""
import json
import os
import base64
import boto3
from boto3.dynamodb.conditions import Attr
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

VALID_STATUSES = {"pending", "in_progress", "completed", "cancelled"}
MAX_LIMIT = 100


def lambda_handler(event, context):
    params = event.get("queryStringParameters") or {}
    status = params.get("status", "").lower()
    limit = min(int(params.get("limit", 20)), MAX_LIMIT)
    encoded_last_key = params.get("lastKey")

    if status and status not in VALID_STATUSES:
        return _response(400, {"error": f"status must be one of: {', '.join(VALID_STATUSES)}"})

    scan_kwargs = {"Limit": limit}

    if status:
        scan_kwargs["FilterExpression"] = Attr("status").eq(status)

    # Decode pagination token
    if encoded_last_key:
        try:
            raw = base64.b64decode(encoded_last_key.encode()).decode()
            scan_kwargs["ExclusiveStartKey"] = json.loads(raw)
        except Exception:
            return _response(400, {"error": "Invalid lastKey pagination token"})

    try:
        result = table.scan(**scan_kwargs)
    except ClientError as e:
        return _response(500, {"error": "Database error", "detail": str(e)})

    items = result.get("Items", [])
    response_body = {"tasks": items, "count": len(items)}

    # Return opaque pagination token
    last_evaluated = result.get("LastEvaluatedKey")
    if last_evaluated:
        token = base64.b64encode(json.dumps(last_evaluated).encode()).decode()
        response_body["nextKey"] = token

    return _response(200, response_body)


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }
