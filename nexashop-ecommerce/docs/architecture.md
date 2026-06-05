# NexaShop Architecture — Decision Record

## System Overview

NexaShop handles three core workloads with distinct scaling and durability requirements:

| Workload | Characteristics | Service Choice |
|----------|----------------|----------------|
| Product catalog reads | High-volume, read-heavy, flexible schema | DynamoDB |
| Order management | ACID transactions, relational joins | Aurora PostgreSQL |
| Session / cart state | Sub-ms reads, TTL expiry | ElastiCache Redis |
| Async order processing | Decoupled, at-least-once, retry-safe | SQS + Lambda |

---

## ADR-001: DynamoDB for Product Catalog

**Decision:** Use DynamoDB with PAY_PER_REQUEST billing for the product catalog.

**Rationale:**
- Product reads vastly outnumber writes (browse:purchase ratio ~100:1)
- Schema flexibility handles product variants (apparel has sizes/colors; electronics have specs)
- Single-digit millisecond reads at any scale without ops overhead
- GSI on category+createdAt supports browse-by-category with recency sort

**Trade-off accepted:** No complex queries (no JOIN, no full-text search). Search is handled by a future OpenSearch integration; category filtering is satisfied by the GSI.

---

## ADR-002: Aurora PostgreSQL for Orders

**Decision:** Use Aurora PostgreSQL Multi-AZ for orders and user data.

**Rationale:**
- Orders require ACID transactions: deducting inventory + creating order + charging payment must be atomic
- Multi-AZ provides automatic failover in < 30 seconds — acceptable for checkout SLA
- Aurora reader endpoint scales read traffic (order history, reporting) without touching the writer
- Performance Insights and Enhanced Monitoring give visibility into slow queries at no extra compute cost

**Trade-off accepted:** Higher cost than DynamoDB (~$130/month for t3.medium Multi-AZ vs ~$28 DynamoDB). Justified by transactional requirements.

---

## ADR-003: SQS for Order Processing (Not Direct Lambda Invocation)

**Decision:** API Lambda writes order to SQS; a separate processor Lambda consumes the queue.

**Rationale:**
- Decouples checkout response time from fulfillment latency — customer gets instant confirmation
- SQS dead-letter queue (DLQ) captures failed messages without data loss
- Visibility timeout (300s) prevents duplicate processing during retries
- Scales independently: checkout API can handle 1000 RPS while processor works through backlog

**Trade-off accepted:** Orders are eventually consistent (not synchronously fulfilled). Acceptable because order confirmation is immediate; fulfillment is a background process.

---

## ADR-004: ECS Fargate (Not EC2) for API Backend

**Decision:** Run the admin/backend API on ECS Fargate containers.

**Rationale:**
- No EC2 instance management, patching, or capacity planning
- Task-level scaling — scale individual API tasks independent of underlying servers
- ECR integration with CI/CD for immutable container deployments
- Better fit for stateless API workloads than long-lived EC2 instances

**Trade-off accepted:** Fargate is ~15-20% more expensive than equivalent EC2 at sustained high load. Accepted because ops savings outweigh compute premium at NexaShop's scale.

---

## ADR-005: Cognito (Not Custom Auth)

**Decision:** Use Amazon Cognito for user authentication and JWT issuance.

**Rationale:**
- Eliminates custom auth code — a primary attack surface for e-commerce platforms
- JWT tokens integrate natively with API Gateway authorizers (zero Lambda auth overhead)
- MFA, advanced security mode, and account recovery are managed features
- Hosted UI + OAuth2 code flow enables future social login (Google, Apple) without architecture changes

**Trade-off accepted:** Cognito's customization is limited compared to Auth0 or custom solutions. Acceptable for NexaShop's current requirements; migration path to Auth0 exists if needs evolve.

---

## ADR-006: One NAT Gateway per AZ

**Decision:** Deploy one NAT Gateway in each Availability Zone.

**Rationale:**
- Single NAT Gateway = single point of failure: if AZ-1a fails, instances in AZ-1b/1c lose outbound internet access even if they are healthy
- Cost: ~$32/month per additional NAT Gateway — cheap insurance for production e-commerce

**Trade-off accepted:** Additional $64/month in NAT Gateway cost.

---

## Network Segmentation

```
10.0.0.0/16 (VPC)
├── 10.0.0.0/20   Public AZ-1a   (ALB, NAT GW)
├── 10.0.16.0/20  Public AZ-1b   (ALB, NAT GW)
├── 10.0.32.0/20  Public AZ-1c   (ALB, NAT GW)
├── 10.0.48.0/20  Private AZ-1a  (ECS tasks, Lambda)
├── 10.0.64.0/20  Private AZ-1b  (ECS tasks, Lambda)
├── 10.0.80.0/20  Private AZ-1c  (ECS tasks, Lambda)
├── 10.0.96.0/20  Isolated AZ-1a (Aurora, ElastiCache)
├── 10.0.112.0/20 Isolated AZ-1b (Aurora, ElastiCache)
└── 10.0.128.0/20 Isolated AZ-1c (Aurora, ElastiCache)
```

**Security Group Chain:**
```
Internet → CloudFront (WAF) → ALB-SG → ECS-SG → RDS-SG (port 5432 from ECS-SG only)
                                              └──→ Redis-SG (port 6379 from ECS-SG only)
```

Database and cache tiers have **zero internet route** and accept connections only from the ECS security group. Not even a bastion host can reach them without SSM Session Manager port forwarding.

---

## Observability Strategy

| Signal | Tool | Threshold |
|--------|------|-----------|
| API 5XX errors | CloudWatch Alarm → SNS | > 10 in 60s |
| Order queue depth | CloudWatch Alarm → SNS | > 500 messages |
| Aurora CPU | CloudWatch Alarm → SNS | > 80% for 5 min |
| Lambda error rate | CloudWatch Alarm → SNS | > 1% in 5 min |
| Slow API responses | X-Ray trace analysis | p99 > 2s |
| Failed auth attempts | Cognito + CloudTrail | Manual review |

All Lambda functions use AWS Lambda Powertools for structured JSON logging, enabling CloudWatch Logs Insights queries without parsing raw text.
