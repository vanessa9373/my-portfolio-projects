# Lab 17: Serverless Event-Driven Data Processing Pipeline — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + Event-Driven Architecture Patterns  
> **Scope:** API Gateway → Lambda (ingestion) → SQS → Lambda (processor) → DynamoDB + S3 — 1M+ events/day

---

## What This Architecture Solves

EC2-based event processing runs servers 24/7 for workloads that are active 20% of the time. The server is provisioned for peak load, which means 80% of capacity is idle during off-peak hours. When traffic spikes beyond the provisioned capacity, events are dropped or queued in memory — and a server crash loses the in-memory queue entirely. This serverless pipeline inverts that model: capacity scales with demand, cost scales with usage, and events are never lost because they're durably stored in SQS before processing begins.

---

## Architecture: Decoupled Event Processing Pipeline

```
Clients
    │ HTTPS POST /events
    ▼
API Gateway (managed HTTPS endpoint, request validation)
    │
    ▼
Lambda: Ingestion Function
    ├── Validate event schema (required fields, type checking)
    ├── Enrich with metadata (timestamp, source IP, request ID)
    └── Publish to SQS (durable buffering)
             │
             ▼
SQS Queue (Standard)
    ├── Visibility timeout: 30s (processor must complete within 30s)
    ├── Message retention: 4 days (buffer against downstream outages)
    └── Redrive policy: maxReceiveCount=3 → Dead Letter Queue
             │
             ▼ (event-source mapping, batch size 10)
Lambda: Processor Function
    ├── Process 10 messages at once (batch write efficiency)
    ├── Write to DynamoDB (real-time query access)
    └── Archive to S3 (long-term storage, analytics)
             │
             ├── DynamoDB (single-digit ms reads, auto-scaling)
             └── S3 (lifecycle: 90 days → Glacier)

             ↓ On failure (3 attempts exhausted)
Dead Letter Queue
    └── CloudWatch alarm → SNS → Slack alert
```

---

## Step-by-Step: Serverless Pipeline

### Step 1 — Infrastructure Deployment

```hcl
# terraform/main.tf (key resources)
resource "aws_sqs_queue" "events" {
  name                       = "analytics-events"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600  # 4 days
  receive_wait_time_seconds  = 20      # long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3  # retry 3 times before DLQ
  })
}

resource "aws_sqs_queue" "events_dlq" {
  name                       = "analytics-events-dlq"
  message_retention_seconds  = 1209600  # 14 days (longer than main queue)
}

resource "aws_lambda_event_source_mapping" "processor" {
  event_source_arn = aws_sqs_queue.events.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10       # process 10 messages per invocation
  
  function_response_types = ["ReportBatchItemFailures"]
  # Allows partial batch failures — failed items go to DLQ;
  # successful items in the same batch are not retried
}
```

**Why `visibility_timeout: 30s` on the SQS queue?**  
When Lambda retrieves a message from SQS, that message becomes invisible to other consumers for the visibility timeout duration. If the Lambda function fails or times out before completing, the message reappears in the queue and can be reprocessed. If the Lambda function runs for more than 30 seconds (the timeout), the message will reappear before processing completes — causing it to be processed twice. The visibility timeout must be at least as long as the Lambda function timeout. Setting them equal ensures messages are retried exactly when Lambda fails, not before.

**Why `maxReceiveCount: 3` rather than a higher number?**  
A message that fails processing 3 times is likely failing for a structural reason (malformed JSON, schema violation, missing required field) rather than a transient reason (temporary DynamoDB capacity shortage, network blip). Retrying 10 times wastes Lambda invocations on events that will never succeed. Three attempts distinguish transient failures (usually succeed on retry 1 or 2) from structural failures (fail all three times and need human investigation in the DLQ).

**Why `receive_wait_time_seconds: 20` (long polling)?**  
Short polling queries SQS immediately, even if the queue is empty — each empty-queue check costs $0.00000040 and consumes a Lambda invocation. Long polling waits up to 20 seconds for a message to arrive before returning an empty response. For a queue that processes 1M events/day (~12 events/second), long polling is unnecessary. For a low-volume queue that has seconds-long quiet periods, long polling reduces cost and Lambda invocations significantly.

### Step 2 — Ingestion Lambda

```python
# src/ingestion/handler.py
import json
import boto3
import uuid
from datetime import datetime, timezone

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['SQS_QUEUE_URL']

REQUIRED_FIELDS = ['event_type', 'user_id']

def lambda_handler(event, context):
    # API Gateway passes body as a string
    body = json.loads(event.get('body', '{}'))
    
    # Schema validation at the boundary
    missing = [f for f in REQUIRED_FIELDS if f not in body]
    if missing:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': f'Missing required fields: {missing}'})
        }
    
    # Enrich with system metadata
    enriched = {
        **body,
        'event_id': str(uuid.uuid4()),        # deduplification key
        'ingested_at': datetime.now(timezone.utc).isoformat(),
        'source_ip': event['requestContext']['identity']['sourceIp'],
        'api_request_id': context.aws_request_id,
    }
    
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(enriched),
        MessageGroupId=body.get('user_id', 'default'),  # FIFO ordering by user
    )
    
    return {'statusCode': 202, 'body': json.dumps({'event_id': enriched['event_id']})}
```

**Why validate the schema in the ingestion Lambda rather than in the processor?**  
The ingestion Lambda is the system boundary — the point where external, untrusted data enters the system. Validating at the boundary means invalid events never reach the SQS queue, never trigger the processor Lambda, and never waste processing capacity. If validation happens in the processor, invalid events still consume SQS capacity, Lambda invocations, and DLQ storage before being rejected. Fail fast at the boundary.

**Why return `202 Accepted` rather than `200 OK`?**  
`200 OK` conventionally means the request was processed. The ingestion Lambda has only placed the event in a queue — processing hasn't happened yet. `202 Accepted` means "we received your request and will process it asynchronously." This is the semantically correct response for an async pipeline and sets accurate expectations for clients about when the data will be queryable.

### Step 3 — Processor Lambda

```python
# src/processor/handler.py
import json
import boto3
from typing import List, Dict

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def lambda_handler(event, context):
    failed_message_ids = []
    
    # Batch write to DynamoDB (up to 25 items per BatchWrite)
    with table.batch_writer() as batch:
        for record in event['Records']:
            try:
                message = json.loads(record['body'])
                
                # DynamoDB write
                batch.put_item(Item={
                    'PK': f"USER#{message['user_id']}",
                    'SK': f"EVENT#{message['ingested_at']}#{message['event_id']}",
                    **message
                })
                
                # S3 archive (partitioned by date for Athena queries)
                date = message['ingested_at'][:10]  # YYYY-MM-DD
                s3.put_object(
                    Bucket=os.environ['ARCHIVE_BUCKET'],
                    Key=f"events/date={date}/{message['event_id']}.json",
                    Body=json.dumps(message)
                )
                
            except Exception as e:
                print(f"Failed to process message {record['messageId']}: {e}")
                failed_message_ids.append({'itemIdentifier': record['messageId']})
    
    # ReportBatchItemFailures: only failed messages go to DLQ
    return {'batchItemFailures': [{'itemIdentifier': mid} for mid in failed_message_ids]}
```

**Why use `table.batch_writer()` rather than individual `put_item` calls?**  
Each individual DynamoDB `put_item` call is one API request. Processing 10 messages with individual puts = 10 DynamoDB API calls. `batch_writer()` buffers up to 25 items and sends them in a single `batch_write_item` API call. For 10 messages: 1 API call instead of 10. DynamoDB's batch write API also handles partial failures (individual item failures) and retries automatically, whereas individual `put_item` errors require manual retry logic.

**Why the `batchItemFailures` response format (partial batch failures)?**  
Without `ReportBatchItemFailures`, if any message in a batch of 10 fails, the entire batch of 10 messages is returned to the SQS queue for retry. The 9 successfully processed messages will be processed again — causing duplicate writes to DynamoDB and S3. With partial batch failure reporting, only the failed message ID is returned; the 9 successful messages are permanently deleted from the queue. This eliminates duplicates and makes the processor naturally idempotent for the success case.

**Why partition S3 objects by `date=YYYY-MM-DD` in the key path?**  
Athena and Glue discover S3 partitions by prefix matching. A partition scheme of `events/date=2026-06-05/` allows Athena to query `WHERE date = '2026-06-05'` and scan only that day's objects — not the entire dataset. Without partitioning, every query scans all objects. For 1M events/day at 1KB each, that's 1GB/day, 365GB/year — partition pruning reduces query cost by 99% for time-bounded queries.

### Step 4 — DynamoDB Data Model

```
Table: analytics-events
Partition key: PK (string) = "USER#<user_id>"
Sort key:      SK (string) = "EVENT#<ingested_at>#<event_id>"

Access patterns supported:
  1. Get all events for a user:       PK = "USER#u123"
  2. Get events for a user in window: PK = "USER#u123", SK between "EVENT#2026-06-01" and "EVENT#2026-06-02"
  3. Get specific event by ID:        PK + SK exact match (with event_id as SK suffix for uniqueness)
```

**Why this key design rather than `event_id` as the partition key?**  
Using `event_id` as the partition key enables only one access pattern: get a specific event by ID. The most common analytical queries are user-centric: "show me all events for user X in the last 7 days." A `USER#` partition key with a timestamp sort key enables that pattern efficiently. The `event_id` suffix on the sort key ensures uniqueness when a user generates multiple events at the same millisecond.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **DLQ with CloudWatch alarm:** Failed events are visible (not silently dropped), alerting fires when DLQ depth > 0, investigation can happen without data loss
- **`202 Accepted` response code:** Clients know processing is async — they don't retry because they assume failure

### Security
- **Schema validation at API Gateway:** Malformed requests are rejected before Lambda is invoked — no Lambda execution cost for invalid events, and injection attacks are prevented at the boundary
- **Lambda IAM roles:** Ingestion Lambda has `sqs:SendMessage` only; Processor Lambda has `dynamodb:BatchWriteItem` and `s3:PutObject` only — no over-privileged roles

### Reliability
- **SQS durability:** Messages are durably stored across multiple AZs before Lambda processes them — a Lambda crash or AZ failure never loses events
- **DLQ for failed events:** After 3 processing attempts, failed events are moved to DLQ rather than discarded — no data loss even for structural failures
- **Partial batch failure reporting:** Only failed messages are retried; successful messages in the same batch are not reprocessed

### Performance Efficiency
- **Batch size 10:** 10 messages per Lambda invocation reduces cold starts per event by 10× vs batch size 1
- **DynamoDB `batch_writer()`:** 1 DynamoDB API call per 10 messages vs 10 individual puts
- **S3 date-partitioned keys:** Athena queries benefit from partition pruning — dramatically reduces query cost for time-bounded analysis

### Cost Optimization
- **70% cost reduction vs EC2:** EC2 provisioned for peak load runs 24/7. Lambda runs only when events arrive. For 1M events/day at 100ms average duration per invocation: Lambda cost = ~$4/month vs EC2 at ~$150/month for an equivalent always-on configuration
- **Long polling:** Eliminates empty-queue SQS API calls during quiet periods
- **DynamoDB on-demand pricing:** No capacity planning for unpredictable event volumes

### Sustainability
- **No idle infrastructure:** Lambda functions consume zero resources when not processing events — no servers idling at 5% CPU utilization between event bursts

---

## Key Architectural Insight

The SQS queue is not a performance optimization — it is a reliability mechanism. Without SQS, the pipeline is `API Gateway → Lambda (ingestion+processing) → DynamoDB`. If DynamoDB throttles (write capacity exceeded), the Lambda function fails, and the API Gateway receives a 500. The client must retry. Under load, all clients are retrying simultaneously, making the DynamoDB throttling worse. With SQS in between, DynamoDB throttling causes Lambda (processor) to slow down — messages queue up in SQS rather than being dropped. When DynamoDB recovers, the processor drains the queue. The client always receives a `202 Accepted` regardless of DynamoDB state. The queue converts a synchronous failure into an asynchronous backlog — which is recoverable, while a dropped request is not.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
