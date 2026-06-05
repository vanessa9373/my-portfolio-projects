# Serverless Task Management API — AWS Lambda + DynamoDB

> **Architect:** Vanessa Awo · AWS Solutions Architect Associate  
> **Stack:** AWS Lambda (Python 3.12 · arm64) · API Gateway HTTP API · DynamoDB · X-Ray · GitHub Actions  
> **Status:** Production-deployed ✅ | CI/CD Pipeline ✅ | Unit Tested ✅ | OIDC Auth ✅

---

## Problem Statement

A team needed a lightweight task management backend with zero infrastructure management overhead, capable of scaling from 0 to 50,000 requests/day without provisioning servers, managing clusters, or paying for idle compute.

**Goal:** Build a fully serverless REST API that costs <$5/month at low traffic, scales automatically at high traffic, and deploys via CI/CD on every merge to `main`.

---

## Architecture

```
Client (curl / Postman / Frontend)
        │
        ▼
  API Gateway HTTP API  ──── CloudWatch Logs + X-Ray Traces
        │
        ├── POST   /tasks          ──► Lambda: create_task  ─┐
        ├── GET    /tasks/{id}     ──► Lambda: get_task      │
        ├── GET    /tasks          ──► Lambda: list_tasks    ├──► DynamoDB Table
        ├── PATCH  /tasks/{id}     ──► Lambda: update_task   │    (PAY_PER_REQUEST)
        └── DELETE /tasks/{id}     ──► Lambda: delete_task  ─┘
                                                               │
                                                    GSI: StatusCreatedAtIndex
                                                    TTL: Auto-expire cancelled tasks
```

---

## API Reference

### POST /tasks — Create a task
```bash
curl -X POST https://abc123.execute-api.us-east-1.amazonaws.com/prod/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Design VPC architecture", "priority": "high", "description": "3-tier VPC across 3 AZs"}'

# Response 201
{
  "taskId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Design VPC architecture",
  "description": "3-tier VPC across 3 AZs",
  "status": "pending",
  "priority": "high",
  "createdAt": "2026-05-30T10:00:00.000Z",
  "updatedAt": "2026-05-30T10:00:00.000Z"
}
```

### GET /tasks/{taskId} — Get one task
```bash
curl https://.../prod/tasks/550e8400-e29b-41d4-a716-446655440000
# Response 200 — task object
# Response 404 — { "error": "Task 'xxx' not found" }
```

### GET /tasks — List tasks with pagination
```bash
# All tasks (default limit 20)
curl "https://.../prod/tasks"

# Filter by status + paginate
curl "https://.../prod/tasks?status=pending&limit=10"

# Next page using opaque token
curl "https://.../prod/tasks?lastKey=eyJ0YXNrSWQiOiAi..."
```

### PATCH /tasks/{taskId} — Update a task
```bash
curl -X PATCH https://.../prod/tasks/550e8400... \
  -H "Content-Type: application/json" \
  -d '{"status": "in_progress", "priority": "critical"}'
# Response 200 — updated task object
```

### DELETE /tasks/{taskId} — Soft-delete (cancel)
```bash
curl -X DELETE https://.../prod/tasks/550e8400...
# Response 200 — { "message": "Task cancelled. Will be deleted in 7 days." }
# DynamoDB TTL removes the item automatically after 7 days
```

---

## Design Decisions

### Why Lambda + DynamoDB (not EC2 + RDS)?
- **Cost:** Pay per 100ms of execution. Zero traffic = $0. This API costs ~$0.20/month at 1M requests.
- **Scale:** DynamoDB scales to millions of requests/second. Lambda scales to 1000 concurrent executions by default.
- **Ops:** No servers to patch, no cluster to manage, no DB connections to pool.
- **Trade-off accepted:** Cold starts (~100–500ms first invocation). Mitigated: arm64 Graviton2 runtime reduces cold starts ~20%.

### Why API Gateway HTTP API (not REST API)?
- HTTP API is 70% cheaper than REST API ($1.00/million vs $3.50/million).
- HTTP API has built-in CORS, JWT authorizers, and faster proxy integration.
- Trade-off: No API keys, usage plans, or request/response transformation (not needed here).

### Why DynamoDB PAY_PER_REQUEST (not provisioned)?
- No capacity planning for a new service with unpredictable traffic.
- PAY_PER_REQUEST scales instantly with no throttling from under-provisioned RCUs/WCUs.
- Switch to provisioned + auto-scaling once traffic patterns are established (usually 3–6 months).

### Why soft-delete with TTL (not hard delete)?
- Audit trail: cancelled tasks remain queryable for 7 days.
- DynamoDB TTL is free and eventually consistent (~48h guarantee) — acceptable for cleanup.
- No cascading foreign-key issues like in relational DBs.

### Why arm64 (Graviton2) Lambda architecture?
- 20% better price-performance vs x86_64 for Python workloads.
- Same code, no changes needed — Python is architecture-agnostic.

### Why GitHub Actions OIDC (not long-lived access keys)?
- OIDC generates temporary STS credentials per workflow run — no secret rotation needed.
- If GitHub is compromised, the blast radius is limited to one workflow run, not permanent key exposure.
- Industry best practice for CI/CD → AWS authentication.

---

## Cost Analysis

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| Lambda | 1M requests × 256MB × 10ms avg | ~$0.02 |
| API Gateway HTTP API | 1M requests | ~$1.00 |
| DynamoDB (PAY_PER_REQUEST) | 1M reads + 100K writes | ~$0.35 |
| CloudWatch Logs | ~1 GB/month | ~$0.50 |
| X-Ray Traces | 1M traces (100K free) | ~$0.45 |
| **Total** | | **~$2.32/month** |

> **vs. EC2 + RDS:** Even a t3.micro ($8.50/month) + RDS t3.micro ($15/month) = $23.50/month with no scaling.

---

## Local Development

```bash
# Install dependencies
pip install boto3 moto pytest pytest-cov

# Run tests (no AWS credentials needed — moto intercepts)
pytest tests/ -v --cov=src

# Test against real AWS (deploy first)
export API_URL=$(cd terraform && terraform output -raw api_endpoint)
curl -X POST "$API_URL/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test task"}'
```

---

## Deploy

```bash
# One-time: set up OIDC trust in AWS IAM (see docs/oidc-setup.md)

# Terraform deploy
cd terraform
terraform init
terraform apply -var="environment=prod"

# Or: push to main branch → GitHub Actions deploys automatically
git push origin main
```

---

## Project Structure

```
02-serverless-task-api/
├── src/handlers/
│   ├── create_task.py     # POST /tasks
│   ├── get_task.py        # GET /tasks/{taskId}
│   ├── list_tasks.py      # GET /tasks (paginated)
│   ├── update_task.py     # PATCH /tasks/{taskId}
│   └── delete_task.py     # DELETE (soft-delete + TTL)
├── tests/
│   └── test_create_task.py # moto-based unit tests (no real AWS)
├── terraform/
│   ├── main.tf            # DynamoDB, Lambda, API GW, IAM, CloudWatch
│   ├── variables.tf
│   └── outputs.tf
└── .github/workflows/
    └── deploy.yml         # Test → Plan (PR) → Apply (main) → Smoke test
```

---

## Skills Demonstrated

- **Serverless architecture:** Lambda, API Gateway, DynamoDB — zero server management
- **IaC:** Terraform with for_each loops, dynamic integrations, remote state
- **Security:** Least-privilege IAM, OIDC (no long-lived keys), DynamoDB encryption at rest
- **CI/CD:** GitHub Actions: test → plan → apply → smoke test pipeline
- **Cost optimization:** arm64 Lambda, HTTP API over REST API, PAY_PER_REQUEST DynamoDB
- **Observability:** X-Ray distributed tracing, CloudWatch alarms on Lambda errors and API 5xx
- **Reliability:** DynamoDB PITR (35-day restore), TTL for auto-cleanup, conditional writes
- **Testing:** moto-based unit tests that mock AWS without real credentials

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
