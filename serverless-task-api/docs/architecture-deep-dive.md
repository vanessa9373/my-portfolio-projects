# Architecture Deep Dive — Serverless Task Management API
## Solutions Architect Analysis · AWS Well-Architected Framework

---

## Executive Summary

This document traces every request through the Serverless Task API — from the first HTTP call to the final DynamoDB write — and explains why every service, configuration, and parameter was chosen. The architecture demonstrates that serverless is not just a cost optimization tactic: it is a fundamentally different operational model that eliminates entire categories of infrastructure problems.

**The core principle:** When you don't have servers, you don't have server problems — no patching, no capacity planning, no idle compute, no "the server rebooted overnight and nobody knows why."

---

## Step 1 — Request Arrives: API Gateway HTTP API

### What happens
A client (browser, mobile app, or `curl`) sends an HTTPS request to the API Gateway invoke URL:
```
POST https://abc123.execute-api.us-east-1.amazonaws.com/prod/tasks
```

### Why API Gateway HTTP API (not REST API, not ALB)

**HTTP API vs REST API:**

| Feature | HTTP API | REST API |
|---------|---------|---------|
| Price | $1.00/million requests | $3.50/million requests |
| Latency | Lower (simpler proxy) | Higher |
| JWT authorizers | Native | Requires Lambda authorizer |
| CORS | Configured in one place | Per-route configuration |
| Request/response transforms | Not supported | Supported |
| API keys / usage plans | Not supported | Supported |

This API does not need request/response transformation, API keys, or usage plans. Choosing REST API would cost 3.5× more for zero additional benefit.

**Why not ALB:** ALB does not natively support JWT authorizer integration. Adding JWT verification would require a Lambda function on every request path. API Gateway HTTP API validates Cognito JWTs natively — zero Lambda cold start on auth checks.

### CORS configuration
```yaml
AllowOrigins: ["https://app.yourclient.com"]
AllowMethods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
AllowHeaders: ["Content-Type", "Authorization"]
MaxAge: 300
```
CORS is configured once at the API level, not per-route. The `MaxAge: 300` tells browsers to cache the CORS preflight response for 5 minutes — reduces OPTIONS requests from 1-per-request to 1-per-5-minutes per origin.

### Throttling
```yaml
DefaultRouteSettings:
  ThrottlingBurstLimit: 1000   # Max concurrent requests
  ThrottlingRateLimit: 500     # Requests per second steady state
```
Throttling prevents a runaway client or DDoS from exhausting Lambda concurrency and incurring unexpected cost. Throttled requests receive HTTP 429 (Too Many Requests) with a `Retry-After` header.

---

## Step 2 — Authentication: JWT Authorizer

### What happens
API Gateway inspects the `Authorization: Bearer <token>` header. It validates the JWT against the Cognito JWKS (JSON Web Key Set) endpoint — without invoking any Lambda function.

### Why JWT (not API keys, not Lambda authorizer)

**API keys:** Suitable for machine-to-machine or developer access. Not suitable for user authentication — API keys don't carry identity claims, can't express user roles, and must be rotated manually.

**Lambda authorizer:** A Lambda function that validates the token and returns an IAM policy. Adds 50-100ms latency on every request (or uses a cache with a 5-minute TTL). Requires you to write and maintain JWT validation code.

**JWT authorizer (native):** API Gateway validates the JWT signature against the Cognito JWKS endpoint, checks expiry, and extracts claims — all natively, at zero latency cost, with no Lambda invocation. The `sub` claim (user ID) is passed directly to the Lambda function in the `requestContext.authorizer.claims` object.

### Token validation steps (what API Gateway does automatically)
1. Extract `Authorization` header
2. Split `Bearer <token>` → extract the JWT
3. Decode the JWT header → get `kid` (key ID)
4. Fetch JWKS from Cognito (cached) → find the matching public key
5. Verify JWT signature using the public key
6. Check `exp` (expiry) — reject if expired
7. Check `aud` (audience) matches the configured Cognito client ID
8. Pass `sub`, `email`, and custom claims to Lambda

If any step fails → HTTP 401 Unauthorized. Lambda is never invoked.

---

## Step 3 — Routing to Lambda

### What happens
API Gateway matches the request method + path to a route and invokes the corresponding Lambda function synchronously.

### Route → Function mapping
```
POST   /tasks         → nexashop-create-task
GET    /tasks/{id}    → nexashop-get-task
GET    /tasks         → nexashop-list-tasks
PATCH  /tasks/{id}    → nexashop-update-task
DELETE /tasks/{id}    → nexashop-delete-task
```

### Why separate Lambda per route (not one monolith Lambda)

**Least-privilege IAM:** Each function has exactly the DynamoDB permissions it needs:
- `create_task` — `dynamodb:PutItem` only
- `get_task` — `dynamodb:GetItem` only
- `list_tasks` — `dynamodb:Query`, `dynamodb:Scan` only
- `update_task` — `dynamodb:UpdateItem` only
- `delete_task` — `dynamodb:UpdateItem` (soft delete via TTL attribute update) only

If `list_tasks` is compromised, it cannot write to DynamoDB. If `create_task` is compromised, it cannot read or delete items. Blast radius is scoped to the specific operation.

**Independent scaling:** Each function scales independently. A burst of GET requests doesn't consume concurrency from POST operations.

**Independent deployment:** Update `list_tasks` without redeploying `create_task`. Zero-risk partial deploys.

---

## Step 4 — Lambda Execution: Python 3.12 on arm64

### Why Python 3.12
- Native `boto3` SDK (AWS SDK for Python) — DynamoDB operations are 3-5 lines
- Clean JSON handling with `json` stdlib
- Fast cold starts for simple CRUD functions (< 200ms on arm64)
- `typing` module for IDE autocomplete and documentation

### Why arm64 (Graviton2) over x86_64
```hcl
architectures = ["arm64"]
```
- 20% better price-performance than x86_64 for Python workloads
- Python is architecture-agnostic — no code changes required
- Same Lambda pricing model, lower compute cost per GB-second
- Cold starts are marginally faster on arm64 due to more efficient runtime initialization

**The math:** At 1M invocations/month with 256MB memory and 10ms average duration:
- x86_64: 1M × 256/1024 GB × 0.01s = 2,500 GB-seconds × $0.0000166667 = $0.042
- arm64: 2,500 GB-seconds × $0.0000133334 = $0.033 (20% cheaper)

Small at this scale. At 100M invocations: $3,300 vs $4,200/month — $900/month difference.

### Why 256MB memory (not 128MB or 512MB)

Lambda memory also determines CPU allocation. At 256MB:
- ~0.25 vCPU allocated
- Sufficient for JSON parsing + DynamoDB SDK + response serialization
- Cold start: ~150ms
- Warm execution: ~5-15ms

At 128MB the runtime is slower (less CPU), cold starts increase to ~300ms. At 512MB you're paying for memory that the function doesn't use.

**The Power of 10 approach:** Profile the function, find the memory where additional allocation no longer reduces duration. 256MB is the inflection point for this workload.

### IAM Execution Role — what it allows and why
```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem"],
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/tasks-prod"
    },
    {
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/create-task:*"
    },
    {
      "Effect": "Allow",
      "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords"],
      "Resource": "*"
    }
  ]
}
```
- DynamoDB permission scoped to the specific table ARN (not `*`)
- CloudWatch Logs scoped to this function's log group (not all Lambda log groups)
- X-Ray requires `*` (no resource-level permission support)
- No S3, no EC2, no IAM, no other permissions — not needed, not granted

### Lambda Environment Variables
```python
TASKS_TABLE = os.environ["TASKS_TABLE"]      # Table name (not hardcoded)
ENVIRONMENT = os.environ["ENVIRONMENT"]      # "prod" or "dev" (for logging verbosity)
```
No secrets in environment variables. Database connection strings don't apply (DynamoDB is an API, not a connection). No credentials needed beyond the IAM role.

### X-Ray Tracing

Every Lambda function has `tracing_config { mode = "Active" }`. This automatically:
1. Creates a trace segment for the Lambda invocation
2. Creates subsegments for DynamoDB API calls
3. Records duration, status, and errors for each subsegment

In the AWS X-Ray console, you can see:
```
API Gateway [5ms] → Lambda cold start [145ms] → Lambda execution [12ms] → DynamoDB PutItem [3ms]
```

This trace answers: "is my Lambda slow, or is DynamoDB slow?" — without adding any logging code.

---

## Step 5 — Data Layer: DynamoDB

### Why DynamoDB (not RDS, not Aurora Serverless)

**RDS/Aurora:** Requires a VPC, subnets, security groups, a DB instance, connection pooling (Lambda → RDS requires RDS Proxy to avoid connection exhaustion), and a connection string with credentials. Total setup: 2-3 hours. For a task management API, this is infrastructure overhead that doesn't serve the use case.

**Aurora Serverless v2:** Scales down but never to zero (minimum 0.5 ACUs = ~$0.06/hour = $43/month idle). For low-traffic APIs, this costs more than provisioned DynamoDB.

**DynamoDB:** API-based (no connection, no connection pool, no VPC required for Lambda), scales to zero (PAY_PER_REQUEST has no idle cost), and a simple task management data model is a perfect fit for a key-value/document store.

### Table Design — every attribute explained

```python
{
  "taskId":      "550e8400-...",    # Partition key — UUID v4, globally unique
  "title":       "Design VPC",      # Required field
  "description": "3-tier VPC",      # Optional
  "status":      "pending",         # pending | in_progress | done | cancelled
  "priority":    "high",            # low | medium | high | critical
  "userId":      "cognito-sub-id",  # Owner — from JWT claims
  "createdAt":   "2026-05-30T...",  # ISO 8601 UTC
  "updatedAt":   "2026-05-30T...",  # Updated on every modification
  "ttl":         1717027200         # Unix timestamp — only set on cancelled tasks
}
```

### Global Secondary Index: `StatusCreatedAtIndex`
```
Hash key: status (S)
Sort key: createdAt (S)
Projection: ALL
```

**Why this GSI exists:** The most common query pattern is "show me all pending tasks, newest first." The base table's partition key is `taskId` — you can't efficiently query "all items where status = pending" on the base table (that's a Scan). The GSI lets you:
```python
table.query(
    IndexName="StatusCreatedAtIndex",
    KeyConditionExpression=Key("status").eq("pending"),
    ScanIndexForward=False,  # newest first
    Limit=20
)
```
This is an efficient Query (not a Scan) — reads only the items with `status = pending`, sorted by `createdAt` descending. Cost: 1 RCU per 4KB of items read. Compared to a Scan (reads every item in the table): orders of magnitude cheaper at scale.

### TTL (Time To Live) — soft delete
```python
# On DELETE /tasks/{id}:
table.update_item(
    Key={"taskId": task_id},
    UpdateExpression="SET #s = :cancelled, #t = :ttl",
    ExpressionAttributeNames={"#s": "status", "#t": "ttl"},
    ExpressionAttributeValues={
        ":cancelled": "cancelled",
        ":ttl": int((datetime.utcnow() + timedelta(days=7)).timestamp())
    }
)
```

**Why soft delete (not hard delete):**
- Audit trail: cancelled tasks remain queryable for 7 days
- Accidental deletion recovery: user deleted a task by mistake? Still accessible for 7 days
- DynamoDB TTL is free — no Lambda, no cron job, no cleanup process needed
- TTL deletion is **eventually consistent** (AWS guarantees items expire within 48 hours of the TTL timestamp) — acceptable for a cleanup mechanism

### Conditional writes — preventing race conditions
```python
# On update_task: only update if the task exists and belongs to the user
table.update_item(
    Key={"taskId": task_id},
    ConditionExpression=Attr("userId").eq(user_id) & Attr("taskId").exists(),
    UpdateExpression="SET title = :title",
    ExpressionAttributeValues={":title": new_title}
)
```
Without the condition expression, user A could update user B's task by guessing the `taskId`. The condition ensures the update only applies if `userId` matches the JWT `sub` claim. DynamoDB evaluates this atomically — no race condition between "check ownership" and "apply update."

### Point-in-Time Recovery (PITR)
```hcl
point_in_time_recovery { enabled = true }
```
PITR maintains a continuous backup of the DynamoDB table for the last 35 days. You can restore to any second within that window. Cost: ~$0.20/GB/month of table data. For a task management app, the table is < 1 GB — cost is negligible vs. the risk of losing user data.

---

## Step 6 — CI/CD Pipeline: GitHub Actions with OIDC

### Why OIDC (not IAM access keys)

**The problem with access keys:**
```
Repository secrets:
  AWS_ACCESS_KEY_ID: AKIAIOSFODNN7EXAMPLE
  AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```
- Keys are long-lived — if leaked, they work until manually rotated
- Keys must be rotated periodically — operationally burdensome
- If the GitHub repository is compromised, an attacker has permanent AWS access
- Keys appear in CI logs if accidentally echoed

**OIDC (OpenID Connect):**
```yaml
permissions:
  id-token: write   # Request OIDC token from GitHub
  contents: read

- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
    aws-region: us-east-1
```

GitHub generates a short-lived OIDC token (JWT) for each workflow run. AWS STS exchanges this JWT for temporary credentials (valid 1 hour). The trust policy on the IAM role restricts which GitHub repository and branch can assume it:
```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": "repo:vanessa9373/serverless-task-api:ref:refs/heads/main"
  }
}
```
Only the `main` branch of `vanessa9373/serverless-task-api` can assume this role. A fork cannot. A feature branch cannot. Credentials expire after 1 hour and cannot be reused.

### Pipeline stages explained

**Stage 1: Test**
```yaml
- run: pytest tests/ -v --cov=src --cov-report=xml
```
Uses `moto` (mock AWS library) to simulate DynamoDB. No real AWS account needed for unit tests — the CI environment is fully offline during testing. Tests validate:
- Input validation (missing required fields → 400)
- DynamoDB call parameters (correct table, correct key)
- Response format (correct status codes, JSON structure)
- Error handling (item not found → 404)

**Stage 2: Terraform Plan (on Pull Request)**
```yaml
- run: terraform plan -out=tfplan
- uses: actions/github-script@v7
  # Post plan output as PR comment
```
Engineers see the exact infrastructure changes before merging. `terraform plan` on PRs answers "what will this change affect?" without applying anything.

**Stage 3: Terraform Apply (on main merge)**
```yaml
- run: terraform apply -auto-approve tfplan
```
Applies the plan from Stage 2. Using `-auto-approve` with the saved plan (not a fresh plan) ensures the applied changes exactly match what was reviewed.

**Stage 4: Smoke Test**
```yaml
- run: |
    API_URL=$(terraform output -raw api_endpoint)
    response=$(curl -sf -X POST "$API_URL/tasks" \
      -H "Content-Type: application/json" \
      -d '{"title": "smoke test"}')
    task_id=$(echo $response | jq -r '.taskId')
    curl -sf "$API_URL/tasks/$task_id"
    echo "Smoke test passed"
```
Creates a real task via the live API and reads it back. If this passes, the entire stack (API Gateway → Lambda → DynamoDB) is working end-to-end. If it fails, the pipeline fails and the team is notified.

---

## AWS Well-Architected Framework Evaluation

### Pillar 1: Operational Excellence
- **IaC:** All infrastructure in Terraform — DynamoDB table, 5 Lambda functions, API Gateway, all IAM roles, CloudWatch alarms
- **CI/CD:** Every merge to main automatically tests, plans, applies, and smoke-tests
- **Zero operational toil:** No servers to patch, no database to tune, no cluster to maintain
- **Improvement:** Add canary deployments (Lambda weighted aliases) for gradual traffic shifting

### Pillar 2: Security
- **No long-lived credentials:** OIDC for CI/CD, IAM roles for Lambda
- **Least-privilege IAM:** Each Lambda function has only the permissions it needs, scoped to the specific table ARN
- **JWT authentication:** API Gateway validates tokens natively — no custom auth code
- **DynamoDB encryption at rest:** Default AWS-managed key (upgrade to CMK for regulated workloads)
- **No VPC required:** DynamoDB is an API endpoint — no network attack surface to manage

### Pillar 3: Reliability
- **Lambda fault tolerance:** Lambda automatically retries internal errors. For synchronous API Gateway invocations, errors are returned to the caller (not retried — appropriate for CRUD APIs)
- **DynamoDB availability:** 99.999% SLA — three-AZ replication built in
- **DynamoDB PITR:** 35-day restore window for accidental data loss
- **API Gateway availability:** Managed service, no single region single point of failure at the Gateway level

### Pillar 4: Performance Efficiency
- **arm64 Lambda:** 20% better price-performance
- **DynamoDB GSI:** Query by status without a full table scan
- **X-Ray tracing:** Identifies slow operations without adding logging overhead
- **DynamoDB DAX consideration:** For read-heavy workloads (e.g., 1M reads/day), DAX adds microsecond caching in front of DynamoDB. Not implemented here — PAY_PER_REQUEST at this scale doesn't justify DAX cost (~$0.17/hour = $122/month minimum).

### Pillar 5: Cost Optimization
- **PAY_PER_REQUEST DynamoDB:** Zero idle cost. 1M reads = $0.25. 1M writes = $1.25.
- **HTTP API over REST API:** 70% cost reduction
- **arm64 Lambda:** 20% compute cost reduction
- **No VPC NAT costs:** Lambda → DynamoDB is an API call, not a VPC-routed connection
- **TTL cleanup:** DynamoDB TTL is free — no Lambda or cron job needed for data cleanup

### Pillar 6: Sustainability
- **Serverless:** Zero idle compute — functions run only when invoked
- **arm64:** More efficient silicon than x86_64
- **DynamoDB:** Shared, managed infrastructure — more energy-efficient than dedicated EC2

---

## End-to-End Request Flow: POST /tasks

```
1.  Client → HTTPS POST /tasks → API Gateway endpoint
2.  API Gateway → Extract Authorization header → JWT validation (Cognito JWKS)
3.  JWT valid? No → HTTP 401 Unauthorized → Client
4.  JWT valid? Yes → Extract sub (user ID) from claims
5.  API Gateway → Route match POST /tasks → Invoke create_task Lambda (synchronous)
6.  Lambda cold start (if first invocation): ~150ms on arm64
7.  Lambda: Parse event body → Validate required fields (title, priority)
8.  Lambda: Generate UUID for taskId → Get current UTC timestamp
9.  Lambda: Call DynamoDB PutItem with the task object
10. DynamoDB: Encrypt item → Write to primary partition
11. DynamoDB: Replicate to two additional AZs (synchronous)
12. DynamoDB: Return success → Lambda
13. Lambda: X-Ray records DynamoDB subsegment duration
14. Lambda: Return HTTP 201 with task object as JSON body
15. API Gateway: Return response to client
16. CloudWatch: Lambda logs execution duration, memory used, request ID
17. X-Ray: Trace assembled → API Gateway to Lambda to DynamoDB visible in console
18. (If CPU alarm fires): CloudWatch → SNS → Email notification
```

Total round-trip time:
- Warm Lambda: ~15-25ms
- Cold start Lambda: ~165-175ms
- DynamoDB write: ~3-5ms
- **End-to-end warm:** < 30ms
- **End-to-end cold:** < 200ms

---

*Vanessa Awo · Solutions Architect · [linkedin.com/in/vanessajen](https://linkedin.com/in/vanessajen) · [jenellavan.com](https://jenellavan.com)*
