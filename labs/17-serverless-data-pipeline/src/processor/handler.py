"""
Processor Lambda — Consumes from SQS, transforms data, writes to DynamoDB and S3.
Author: Jenella Awo
"""

import json
import os
import logging
from datetime import datetime

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
BUCKET_NAME = os.environ["S3_BUCKET"]
table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """Process SQS batch of events."""
    success_count = 0
    failure_count = 0

    for record in event.get("Records", []):
        try:
            message = json.loads(record["body"])

            # Transform and enrich
            processed = {
                "event_id": message["event_id"],
                "timestamp": message["timestamp"],
                "event_type": message["event_type"],
                "user_id": message["user_id"],
                "processed_at": datetime.utcnow().isoformat() + "Z",
                "ttl": int(datetime.utcnow().timestamp()) + (90 * 86400),  # 90-day TTL
            }

            # Write to DynamoDB
            table.put_item(Item=processed)

            # Archive to S3
            date_prefix = datetime.utcnow().strftime("%Y/%m/%d/%H")
            s3_key = f"events/{date_prefix}/{message['event_id']}.json"
            s3.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=json.dumps(processed),
                ContentType="application/json",
            )

            success_count += 1

        except Exception as e:
            logger.error(f"Failed to process record: {str(e)}")
            failure_count += 1

    logger.info(f"Processed: {success_count} success, {failure_count} failures")

    # Return batch item failures for partial batch response
    if failure_count > 0:
        return {
            "batchItemFailures": [
                {"itemIdentifier": r["messageId"]}
                for r in event["Records"][-failure_count:]
            ]
        }

    return {"batchItemFailures": []}
