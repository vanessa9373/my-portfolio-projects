# NexaShop — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** End-to-end request flows — Browse → Cart → Checkout → Order Fulfillment

---

## What This Architecture Solves

E-commerce platforms have three workloads with fundamentally different performance and consistency requirements:

| Workload | Read/Write ratio | Consistency required | Latency target |
|----------|-----------------|---------------------|----------------|
| Product catalog | 100:1 reads | Eventual | < 10ms |
| Shopping cart | 10:1 reads | Strong (per user) | < 5ms |
| Orders / payments | 1:3 writes | Strict ACID | < 500ms |

A single database cannot optimize for all three. NexaShop uses polyglot persistence — the right database for each workload — and asynchronous order processing to decouple checkout response time from fulfillment complexity.

---

## Architecture Overview

```
Browser / Mobile Client
        │ HTTPS
        │
[CloudFront Distribution]
        │ WAF (OWASP Top 10, rate limiting, SQLi/XSS rules)
        │
        ├─── Static assets (S3 OAC) ──► React bundle, images, CSS
        │
        └─── /api/* ──► API Gateway HTTP API
                              │ Cognito JWT Authorizer
                              │
               ┌──────────────┼──────────────┐
               │              │              │
        [Products λ]   [Orders λ]     [Cart λ]
               │              │              │
        DynamoDB         Aurora PostgreSQL  ElastiCache Redis
        (catalog)        Multi-AZ          (sessions)
                              │
                         SQS Queue
                              │
                    [Order Processor λ]
                              │
                         SES (email)
```

---

## Step-by-Step: Product Browse Flow

### Step 1 — User Requests the Storefront

Browser requests `https://nexashop.com`. DNS resolves to CloudFront distribution.

**Why CloudFront as the entry point, not direct S3 or ALB?**

CloudFront operates at 450+ PoPs globally. A user in Singapore requesting a React bundle from an S3 bucket in `us-east-1` experiences ~180ms TCP + TLS overhead before the first byte. CloudFront serves the cached bundle from the nearest PoP at ~15ms. For a React SPA where the entire application loads on first request, edge caching cuts initial page load time by 90%.

Additionally, CloudFront is where WAF runs. Placing WAF at CloudFront means malicious traffic is evaluated and dropped in the originating region — it never reaches the application tier. A SQLi attack from an IP in Frankfurt is blocked in Frankfurt, not in `us-east-1` after traversing the Atlantic.

### Step 2 — WAF Evaluation at CloudFront

AWS WAF rules evaluated on every request (in order):

1. **AWS Managed Rules — Core Rule Set (CRS):** Blocks OWASP Top 10 patterns — SQLi in query strings, XSS in headers, path traversal attacks
2. **AWS Managed Rules — SQL database:** Additional SQLi patterns specific to database backends
3. **Rate limiting rule:** IP-based — if an IP exceeds 2,000 requests per 5 minutes, block for 5 minutes. Prevents credential stuffing against `/api/auth/login`
4. **Geo restriction (optional):** Block countries where NexaShop has no operations and sees only bot traffic
5. **Custom rules:** Block requests with `User-Agent` strings matching known scraping frameworks (Scrapy, curl-based scrapers targeting the product catalog)

**Why managed rules instead of custom rules for OWASP?**  
AWS maintains the managed CRS rule set. When a new CVE is disclosed (e.g., Log4Shell generating `${jndi:ldap://...}` patterns in `User-Agent` headers), AWS updates the managed rule set within hours. Custom rules require a human to write, test, and deploy — which takes days. For known attack patterns, managed rules are faster and more comprehensive.

### Step 3 — React App Loads from S3 via OAC

CloudFront fetches the React bundle from S3 using Origin Access Control (OAC).

**Why OAC instead of OAI (Origin Access Identity)?**  
OAI uses a special CloudFront identity that S3 recognizes via bucket policy. OAC is the newer mechanism that uses signed SigV4 requests — CloudFront signs each S3 request with AWS credentials at the edge. OAC supports all S3 operations (including `GetObject` with `ChecksumAlgorithm`), supports SSE-KMS buckets (OAI doesn't work with SSE-KMS), and is AWS's recommended approach as of 2022.

**S3 bucket configuration:**
- Block All Public Access: enabled (bucket has no public access policy)
- Bucket policy: allow `s3:GetObject` from CloudFront service principal with source ARN condition matching the specific distribution
- No static website hosting enabled — CloudFront handles routing, not S3

**Why no static website hosting?** S3 static website hosting generates an HTTP endpoint, not HTTPS. CloudFront provides HTTPS with ACM certificate. Using S3 REST API endpoint via OAC keeps all access HTTPS-only.

### Step 4 — React App Calls `/api/products?category=electronics`

The React app makes an API call. CloudFront forwards `/api/*` requests to API Gateway HTTP API.

**Why HTTP API, not REST API?**

| Feature | HTTP API | REST API |
|---------|----------|----------|
| Price | $1.00/M requests | $3.50/M requests |
| JWT authorizer | Native, zero Lambda overhead | Requires Lambda authorizer |
| Latency | ~1ms overhead | ~6ms overhead |
| Missing from REST | Usage plans, request transformation | — |

NexaShop doesn't need usage plans (rate limiting is at WAF/CloudFront) or request transformation (Lambda functions handle their own mapping). HTTP API is 71% cheaper and has lower latency — straightforward choice.

### Step 5 — Cognito JWT Authorizer Validates the Token

For authenticated endpoints (cart, orders, checkout), API Gateway evaluates the `Authorization: Bearer <JWT>` header.

**JWT validation flow (all within API Gateway — no Lambda invoked):**

1. API Gateway retrieves the Cognito JWKS (JSON Web Key Set) from `https://cognito-idp.us-east-1.amazonaws.com/<pool_id>/.well-known/jwks.json`
2. JWKS is cached — not re-fetched on every request
3. API Gateway decodes the JWT header, extracts `kid` (key ID)
4. Finds the matching public key in the cached JWKS
5. Verifies the RS256 signature using the public key
6. Validates `exp` (token not expired), `iss` (issued by the correct Cognito pool), `aud` (intended for this API)
7. If all checks pass, API Gateway forwards the request to Lambda with the `$context.authorizer.claims` populated

**Why Cognito instead of custom JWT issuance?**

Custom auth requires: a token issuance Lambda, a token validation Lambda, a key rotation mechanism, a revocation list (for logout), brute-force protection, and MFA support. Each of these is a security feature that Cognito provides as a managed service. Custom auth code is an attack surface — Cognito is a hardened service maintained by AWS with dedicated security teams.

**Why RS256 (asymmetric) not HS256 (symmetric)?**  
HS256 uses a shared secret — the same key signs and verifies. If the API ever exposes the signing key, all tokens can be forged. RS256 uses a private key (Cognito holds it, never exposed) to sign and a public key (JWKS endpoint, publicly accessible) to verify. The verification key is public by design — no secret is shared.

### Step 6 — Products Lambda Queries DynamoDB

The Products Lambda receives the request and queries DynamoDB:

```python
response = table.query(
    IndexName='category-createdAt-index',
    KeyConditionExpression=Key('category').eq('electronics') & Key('createdAt').gte(one_month_ago),
    Limit=24,
    ScanIndexForward=False  # most recent first
)
```

**Why DynamoDB for product catalog:**

The product catalog has a read:write ratio of approximately 100:1. Products are added/updated infrequently; they are read millions of times per day during browse sessions. DynamoDB's architecture is optimized for this pattern:

- **Single-digit millisecond reads at any scale:** No connection pool exhaustion, no query planner overhead, no table locking. Each read is a direct key lookup in a B-tree partition
- **PAY_PER_REQUEST billing:** Catalog traffic is highly variable — low overnight, peaks during marketing campaigns. PAY_PER_REQUEST means $0 when idle, scales to handle 10× spikes without provisioning
- **Schema flexibility:** A `laptop` has `RAM`, `CPU`, `storage_gb`. A `t-shirt` has `size`, `color`, `material`. DynamoDB stores each as an item without requiring a shared schema — no nullable columns, no `ALTER TABLE ADD COLUMN` migrations

**GSI design decision:**

The Global Secondary Index `category-createdAt-index` has:
- Partition key: `category` (allows Query — O(log n) — instead of Scan — O(n))
- Sort key: `createdAt` (allows range queries within a category, sorted by recency)

Without the GSI, filtering by category would require a Scan of the entire products table — at 500,000 products, that's 500,000 reads per page load. The GSI reduces this to a targeted Query returning only electronics items, ordered by recency, with pagination via `LastEvaluatedKey`.

**Why arm64 (Graviton2) Lambda:**  
Products Lambda runs on `arm64` architecture. Graviton2 processors provide the same performance as x86 Lambda but at 20% lower price per GB-second. At 50M catalog requests/month × 200ms average duration × 256MB memory:

```
x86:  50M × 0.2s × 256/1024 GB × $0.0000166667/GB-s = $41.67/month
arm64: 50M × 0.2s × 256/1024 GB × $0.0000133334/GB-s = $33.33/month
Savings: $8.34/month — 20% reduction
```

---

## Step-by-Step: Cart Flow (ElastiCache Redis)

### Step 7 — Add to Cart Request

User clicks "Add to Cart." React app calls `PUT /api/cart/{userId}/items`.

Cart Lambda receives the request with the user's Cognito sub (user ID from JWT claims) and the product to add.

**Why ElastiCache Redis for cart state:**

The cart has three requirements that make Redis the optimal choice:

1. **Sub-millisecond latency:** A user adding an item to their cart should see an immediate response. Redis in-memory operations complete in < 1ms. Aurora PostgreSQL would add 2–5ms of disk I/O + connection overhead for every cart update
2. **TTL-based expiry:** Abandoned carts should auto-expire. Redis native `EXPIRE` command sets a TTL on the entire cart key — no cron job, no background worker needed to clean up old sessions
3. **Session affinity is not required:** Redis is accessed by key (`cart:{userId}`) — any Lambda instance can read or write any user's cart without sticky session requirements

```python
# Set cart with 7-day TTL
redis_client.setex(
    f"cart:{user_id}",
    7 * 24 * 3600,  # 7 days in seconds
    json.dumps(cart_items)
)
```

**Why not DynamoDB for cart?**  
DynamoDB's `$0.00065 per read unit` at < 4KB is not free — and cart updates are frequent (add, remove, update quantity). More importantly, DynamoDB's TTL feature doesn't guarantee immediate deletion — items can persist up to 48 hours after expiry. Redis `EXPIRE` is precise. For session data where staleness could mean a user sees items they removed yesterday, Redis TTL is preferable.

**Why ElastiCache Redis over ElastiCache Memcached?**  
Redis supports complex data types (lists, sorted sets, hashes). Cart items are a list of `{product_id, quantity, price}` objects. Redis HASH allows field-level updates (`HSET cart:{id} product_123 '{"qty":2}'`) without reading and rewriting the entire cart. Memcached supports only string values — every cart update requires a full read-modify-write cycle.

### Step 8 — Redis Cluster Mode

ElastiCache Redis is deployed in cluster mode disabled (single primary, two read replicas) for NexaShop's scale.

**Why not cluster mode?** NexaShop's cart data fits in a single Redis shard (< 100GB). Cluster mode adds complexity (slot hashing, cross-slot transaction limitations) without benefit at this scale. Single primary + replicas provides:
- Read scaling via replica endpoint for cart reads
- Automatic failover in < 60 seconds if primary fails (Multi-AZ enabled)
- In-transit encryption (TLS) + at-rest encryption (AES-256) via ElastiCache

---

## Step-by-Step: Checkout Flow

### Step 9 — Checkout Request Initiates a Transaction

User clicks "Place Order." React calls `POST /api/orders/checkout` with cart contents, payment token, and shipping address.

Orders Lambda receives the request. The checkout flow requires ACID guarantees:

```
BEGIN TRANSACTION
  INSERT INTO orders (id, user_id, total, status) VALUES (...)
  INSERT INTO order_items (order_id, product_id, qty, price) VALUES (...)
  UPDATE inventory SET qty = qty - ordered_qty WHERE product_id = ? AND qty >= ordered_qty
  -- if inventory update affected 0 rows → ROLLBACK (out of stock)
COMMIT
```

If the Lambda times out or crashes between INSERT INTO orders and UPDATE inventory, the transaction rolls back automatically. The customer never sees a partial order.

**Why Aurora PostgreSQL instead of DynamoDB for orders:**

DynamoDB transactions exist (`TransactWriteItems`) but have significant limitations:
- Maximum 100 items per transaction
- No row-level locking — optimistic concurrency only (conditional expressions)
- No foreign key constraints — order_items can reference a non-existent order_id
- No SQL joins — generating an order history report with items requires multiple round trips

Orders require relational integrity (order_items foreign keys to orders), complex queries (order history with items, admin reporting), and true ACID transactions across multiple entities. Aurora PostgreSQL provides all of these as a managed service — same AWS-native, same IAM integration, with full PostgreSQL compatibility.

**Aurora vs RDS PostgreSQL:**

| Feature | Aurora PostgreSQL | RDS PostgreSQL |
|---------|-----------------|----------------|
| Storage | Auto-scales to 128TB | Fixed, requires resize |
| Failover | < 30 seconds | 60–120 seconds |
| Read replicas | Up to 15, globally | Up to 5 |
| Replication | Shared storage (no data loss) | Async (1–2 WAL segment lag) |
| Cost | ~20% more | Lower |

Aurora's shared storage architecture means failover switches the endpoint with zero data loss — the standby doesn't need to catch up because both primary and standby write to the same distributed storage layer. For an orders database, zero data loss on failover is worth the 20% premium.

### Step 10 — Order Written to SQS

After the database transaction commits, Orders Lambda puts a message on SQS:

```python
sqs.send_message(
    QueueUrl=ORDER_QUEUE_URL,
    MessageBody=json.dumps({
        'order_id': order_id,
        'user_id': user_id,
        'items': items,
        'email': user_email
    }),
    MessageGroupId=order_id  # for FIFO ordering per order
)
```

Orders Lambda returns `HTTP 201 Created` to the user immediately. The user sees "Order confirmed" before fulfillment begins.

**Why SQS decoupling instead of synchronous fulfillment:**

Fulfillment involves: updating inventory, sending confirmation email, potentially calling a third-party shipping API, and recording fulfillment status. Any one of these can be slow or temporarily unavailable. If all of this happened synchronously during checkout:

- A slow SES email delivery (2–3 seconds) would delay the user's checkout confirmation
- A shipping API timeout would fail the entire checkout transaction
- A spike in order volume (Black Friday) would queue checkout requests behind slow fulfillment work

With SQS decoupling, the checkout Lambda's only responsibility is: validate the order, write to Aurora, put a message on SQS. That's deterministically fast. Fulfillment complexity runs asynchronously.

**SQS configuration decisions:**

- **Visibility timeout: 300 seconds** — If the processor Lambda crashes after receiving the message but before deleting it, the message becomes visible again after 5 minutes. This is longer than the maximum Lambda execution time (15 minutes — but the processor function is much faster) to prevent two instances from processing the same order
- **Dead-letter queue (DLQ):** After 3 failed processing attempts, the message moves to the DLQ. Operations team is alerted. The order exists in Aurora (it was committed) — the DLQ entry is investigated and reprocessed manually
- **Max receive count: 3** — Three attempts before DLQ. Protects against poison pill messages (orders that consistently crash the processor)

### Step 11 — Order Processor Lambda Fulfills the Order

Order Processor Lambda is triggered by SQS event source mapping (batch size: 1).

**Why batch size 1 for orders?** Orders are not events where batch processing makes sense — each order is an independent business transaction. Batch size 1 ensures that if one order fails, it doesn't block the processing of other orders in the batch. The SQS event source mapping only deletes a message from the queue when the Lambda invocation succeeds.

Processor flow:
1. Parse order message
2. Update Aurora `orders` table: `status = 'processing'`
3. Update inventory in Aurora (decrement stock)
4. Call SES to send order confirmation email
5. Update Aurora `orders` table: `status = 'fulfilled'`
6. Delete message from SQS (implicit — Lambda success triggers deletion)

If Step 4 (SES) fails, Lambda throws an exception. SQS retains the message (visibility timeout expires), tries again up to 3 times. If SES is down for an extended period, messages accumulate in the queue — they are not lost. When SES recovers, the processor works through the backlog.

### Step 12 — SES Email Confirmation

AWS Simple Email Service sends the order confirmation.

**Why SES instead of a third-party email provider:**
- No external API dependency — SES is an AWS service, same SLA as the rest of the stack
- No per-email price above the Lambda execution cost — SES is $0.10 per 1,000 emails
- Suppression list management, bounce/complaint handling, and domain verification are managed
- IAM-controlled: only Order Processor Lambda role has `ses:SendEmail` permission — no SMTP credentials to manage or rotate

---

## CI/CD Pipeline Flow

### Step 13 — Developer Pushes Code to GitHub

GitHub Actions workflow triggers on push to `main`.

**3-job parallel pipeline:**

```
Job 1: Lambda Deploy (5 min)
├── Set up Python 3.11
├── pip install -r requirements.txt -t lambda_layer/
├── zip Lambda handlers + dependencies
└── aws lambda update-function-code --zip-file

Job 2: ECS Deploy (8 min)
├── Configure AWS credentials via OIDC
├── docker build admin-api/
├── docker push ECR
└── aws ecs update-service --force-new-deployment

Job 3: Frontend Deploy (4 min)
├── npm ci && npm run build
├── aws s3 sync dist/ s3://nexashop-frontend-bucket/
└── aws cloudfront create-invalidation --paths "/*"
```

**Why OIDC instead of AWS access keys in GitHub Secrets?**

Long-lived AWS access keys in GitHub Secrets:
- Are stored in GitHub's secrets store (trust GitHub's security posture)
- Must be rotated manually — and rotation requires updating the secret in GitHub
- If the repository is compromised, the key provides AWS access until it's rotated
- Show up in CloudTrail as the IAM user that made calls — no attribution to specific pipeline runs

OIDC (OpenID Connect) trust:
- GitHub presents an OIDC token signed by GitHub's identity provider when the workflow runs
- AWS STS evaluates the token against an IAM role trust policy that specifies the exact repository and branch
- STS issues temporary credentials (1-hour TTL) — no persistent secret exists
- CloudTrail shows `sts:AssumeRoleWithWebIdentity` with the GitHub OIDC claim as the principal — attributable to the exact workflow run

**CloudFront invalidation:** After `aws s3 sync` uploads the new React bundle, CloudFront edges still serve the old cached version. `aws cloudfront create-invalidation --paths "/*"` tells all 450+ edge locations to evict their cache. The next request to each edge fetches the new bundle from S3. Invalidation completes in < 60 seconds globally.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence

- **Infrastructure as Code:** All resources defined in Terraform. `terraform plan` shows exactly what changes before apply. New environments can be provisioned in < 30 minutes
- **CI/CD automation:** No manual deployments. Every change goes through GitHub Actions with automated testing before reaching production
- **Runbooks for failure modes:** DLQ alerts trigger an investigation runbook — documented steps for replaying failed orders
- **Three separate deployment jobs:** Lambda, ECS, and Frontend deploy independently. A failed Frontend deploy doesn't block a Lambda fix

### Security

- **No long-lived credentials in CI:** OIDC means zero AWS credentials stored in GitHub
- **WAF at CloudFront edge:** OWASP Top 10 blocked before entering the VPC
- **Secrets Manager for database credentials:** Aurora master password stored in Secrets Manager. Lambda retrieves at runtime — no credentials in environment variables or code
- **Cognito JWT — no custom auth code:** Eliminates a high-value attack surface
- **S3 OAC — no public bucket policy:** Product images and the React bundle are not publicly accessible via S3 URLs — only via CloudFront
- **KMS encryption:** DynamoDB, Aurora, ElastiCache all encrypted at rest with KMS CMK — organization-controlled key policy with CloudTrail audit

### Reliability

- **Aurora Multi-AZ:** < 30-second failover for the orders database — automatic, no manual intervention
- **DynamoDB global tables (optional):** Product catalog can be replicated to a second region for disaster recovery
- **SQS decoupling:** Order data is never lost — SQS retains messages even if the processor is down for hours
- **DLQ:** Failed orders don't disappear — they wait in the DLQ for investigation and reprocessing
- **ElastiCache Multi-AZ:** Redis primary in one AZ, replica in another — automatic failover for cart state
- **Lambda automatic scaling:** 1,000 concurrent executions per Lambda by default, soft limit increase available — handles traffic spikes without provisioning

### Performance Efficiency

- **CloudFront caching:** Static assets served from edge — 90% latency reduction for global users
- **DynamoDB GSI:** Category browse is a Query (O(log n)) not a Scan (O(n)) — consistent performance regardless of catalog size
- **Redis for cart:** Sub-millisecond cart operations — no connection pooling overhead, no disk I/O
- **arm64 Lambda:** 20% cost reduction with equivalent performance — same code, Graviton2 processor
- **Aurora reader endpoint:** Order history reads go to read replicas — writer instance handles only transactional writes

### Cost Optimization

- **DynamoDB PAY_PER_REQUEST:** Zero cost during off-hours. Scales to 10× traffic spikes without provisioning
- **Lambda serverless:** Zero compute cost when idle. No EC2 instances running overnight
- **HTTP API over REST API:** 71% cheaper for identical functionality at NexaShop's feature requirements
- **S3 + CloudFront over EC2 web server:** Static asset delivery is essentially free at scale — no compute
- **Estimated $297/month vs $1,800/month on-prem:** 83% cost reduction accounting for EC2, license, networking, and ops overhead

### Sustainability

- **Serverless where possible:** Lambda and DynamoDB consume compute only during active requests — zero idle resource consumption
- **Graviton2 processors:** arm64 is more energy-efficient per compute unit than x86
- **CloudFront caching:** Fewer origin requests = fewer Lambda invocations = lower total compute

---

## Key Architectural Insight

The design principle behind NexaShop is **workload-appropriate storage and processing**. The three workloads (catalog, cart, orders) have different characteristics — read:write ratio, consistency requirements, latency targets, and query patterns. Mapping each to the right service:

- DynamoDB handles 100× read amplification on catalog
- Redis handles sub-ms cart operations with built-in TTL
- Aurora handles ACID transactions for financial operations

This is the polyglot persistence pattern. It's more complex to operate than a single relational database, but it's the architecture that actually matches the workload — not the one that's easiest to explain.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
