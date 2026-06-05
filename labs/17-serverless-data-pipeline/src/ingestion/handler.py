"""
Ingestion Lambda — Receives API Gateway events, validates, and publishes to SQS.
Author: Jenella Awo
"""

import json
import os
import uuid
import logging
from datetime import datetime

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["SQS_QUEUE_URL"]

REQUIRED_FIELDS = ["event_type", "user_id"]

def handler(event, context):
    """Process incoming API Gateway requests and forward to SQS."""
    try:
        body = json.loads(event.get("body", "{}"))

        # Validate required fields
        missing = [f for f in REQUIRED_FIELDS if f not in body]
        if missing:
            return response(400, {"error": f"Missing required fields: {missing}"})

        # Enrich the event
        message = {
            "event_id": str(uuid.uuid4()),
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "source": "api-gateway",
            **body,
        }

        # Publish to SQS
        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(message),
            MessageAttributes={
                "event_type": {
                    "DataType": "String",
                    "StringValue": body["event_type"],
                }
            },
        )

        logger.info(f"Event ingested: {message['event_id']}")

        return response(200, {
            "status": "accepted",
            "event_id": message["event_id"],
        })

    except json.JSONDecodeError:
        return response(400, {"error": "Invalid JSON payload"})
    except Exception as e:
        logger.error(f"Ingestion error: {str(e)}")
        return response(500, {"error": "Internal server error"})


def response(status_code, body):
    """Create a standardized API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body),
    }
