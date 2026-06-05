# AWS APAC Forage — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** Full SE engagement — Discovery → Architecture → Stakeholder Communication → Objection Handling

---

## What This Engagement Demonstrates

This is not a pure infrastructure architecture document. This is a Solutions Engineer simulation — the full pre-sales motion from the moment a client brief lands to the moment the client approves the architecture. The technical architecture is one deliverable; the communication, discovery, and objection handling are equally scored competencies.

The correct SA/SE answer here is not "which service has the best throughput?" — it is "which service is right for this team's capability, this client's budget, and this growth trajectory?"

---

## The Client Problem (Discovery Phase)

### Step 1 — Receiving and Analyzing the Client Brief

The client brief described:
- APAC growth-stage company with a website experiencing slow response times and outages
- ~500 concurrent users at baseline, spikes to 2,000+ during marketing campaigns
- Single EC2 instance with no load balancing, database failover, or CDN
- Small ops team (3 engineers total, none with AWS Operations certification)
- Current AWS bill: ~$70/month

**What a discovery phase actually produces:**  
Before designing anything, map the current state to identify failure modes. This is the SA skill of turning "our site is slow" into a structured problem statement with specific, addressable failure modes.

### Step 2 — Current-State Architecture Mapping

| Component | Current State | Failure Mode |
|-----------|--------------|-------------|
| Compute | Single EC2 t2.micro | Any EC2 failure = full outage. No health checks. Manual restart required. |
| Database | Single RDS t2.micro, single AZ | Any hardware failure in the AZ = full database outage. No standby. |
| Static assets | Served from EC2 | Static images routed all the way to us-east-1 for every APAC request |
| Deployments | SSH into EC2, `git pull`, `systemctl restart` | Every deployment risks downtime. No rollback mechanism. |
| Scaling | Fixed t2.micro size | Cannot handle traffic spikes. Peak demand = outage. |
| Load balancing | None | EC2 IP directly in DNS. IP change = DNS propagation delay. |

**Root cause (stated explicitly to the client):**  
"This architecture was designed for a startup that needed something running quickly. Every component is a single point of failure. The architecture hasn't scaled with the business — it was never intended to handle 2,000 concurrent users or production-level reliability."

This framing is important: it's not that the original team made a mistake — they made the right call for where the company was. The architecture needs to evolve to match where the company is going.

---

## Architecture Designed

### Step 3 — Selecting Compute: Elastic Beanstalk over EC2, ECS, or EKS

**The SA decision matrix:**

| Option | Technical quality | Ops overhead | Right for this client? |
|--------|------------------|--------------|----------------------|
| Raw EC2 + ALB | Good | High | No — requires manual ASG, launch template, health checks, patching |
| ECS Fargate | Better | Medium | Maybe — requires Docker knowledge the team doesn't have |
| EKS | Best at scale | Very high | No — requires Kubernetes expertise, $0.10/hour cluster fee, complex debugging |
| Elastic Beanstalk | Good | Low | Yes — managed ALB + ASG + platform updates, deploy via Git push |

**Why Elastic Beanstalk is the right answer for this client (not the technically superior answer):**

EKS is objectively more powerful than Elastic Beanstalk. But the client's ops team cannot operate Kubernetes. Deploying EKS would mean:
- Three engineers learning Kubernetes, kubectl, helm, and cluster operations
- 3–6 months of productivity lost to learning curve
- High probability of misconfiguration causing incidents (the original problem)
- Beanstalk → EKS migration required again 18 months later as the team grows

Elastic Beanstalk provides:
- Managed Auto Scaling Group behind a managed Application Load Balancer
- Health checks and automatic unhealthy instance replacement
- `eb deploy` or Git-based deployment — one command, no manual SSH
- Managed platform updates — AWS patches the runtime (Amazon Linux 2, Python, Node.js) automatically
- CloudWatch integration out of the box — no custom metrics setup needed

The right architecture for a 3-person team is the architecture they can operate at 2am during an incident without running a runbook they've never read. Elastic Beanstalk satisfies the operational requirement.

**ADR-001 decision recorded:**  
> Elastic Beanstalk over ECS/EKS. Rationale: client ops capability. EKS is technically superior but operationally incorrect for a 3-person team with no container expertise. Revisit in 12 months as team grows.

### Step 4 — Auto Scaling Configuration

```
Elastic Beanstalk Environment
├── Auto Scaling Group
│   ├── Min instances: 2 (redundancy — one per AZ)
│   ├── Max instances: 8 (handles 4× peak load)
│   └── Target tracking: CPU 65% (30% buffer for scale-out lag)
│
└── Application Load Balancer
    ├── HTTP → HTTPS redirect
    ├── Health check: GET /health every 30s
    └── Sticky sessions: disabled (stateless application)
```

**Why CPU 65% target, not 80%?**  
Auto Scaling has a reaction time. The ASG detects the CPU breach, launches an EC2 instance, waits for it to pass health checks, and adds it to the ALB — this takes 3–5 minutes. If the target is 80%, by the time the new instance is ready, CPU may already be at 95% and users are experiencing degraded performance. A 65% target provides a 30% buffer — new capacity is provisioned while the application still has headroom.

**Why min=2, not min=1?**  
A single instance means single point of failure. If the EC2 instance undergoes hardware failure, the ASG launches a replacement — but during that 3–5 minute window, the site is completely down. With min=2 across two AZs, any single instance failure leaves the other AZ fully operational. The ALB detects the failed instance via health checks (within 30 seconds) and stops routing traffic to it. Zero downtime.

**The restaurant analogy (stakeholder communication):**

> "Right now, your website is like a restaurant with one waiter. During dinner rush, your single waiter is overwhelmed — customers wait too long and eventually leave. Auto Scaling is like a restaurant that automatically calls in more waitstaff when the queue gets long, and sends them home when it quiets down. You only pay for each waiter while they're actually working."

This analogy maps the technical concept to a mental model the client already has:
- "Waiter" = EC2 instance
- "Queue gets long" = CPU above target threshold
- "Calls in more waitstaff" = ASG launching new instance
- "You only pay while they're working" = pay-per-instance-hour

The client understood Auto Scaling immediately and approved in the first meeting.

### Step 5 — Database: RDS Multi-AZ

```
Current:  Single RDS MySQL t2.micro (single AZ)
Designed: RDS MySQL db.t3.medium, Multi-AZ

RDS Multi-AZ Architecture:
  Primary:  us-east-1a
      │ Synchronous replication (before write acknowledgment)
  Standby:  us-east-1b
      │ Same data, different hardware, different AZ
  
  Failover trigger: Primary AZ failure, network disruption, or manual promotion
  Failover time: < 2 minutes (DNS CNAME flips to standby)
  Application change required: None (RDS endpoint DNS is the same)
```

**Why Multi-AZ over a Read Replica?**

Read Replicas are for read scaling — they reduce read load on the primary by distributing queries. But they use asynchronous replication — the replica may be seconds behind the primary. Promoting a read replica to primary requires manual intervention and may lose recent transactions (the replication lag).

Multi-AZ is for availability — the standby uses synchronous replication (the write is not acknowledged until both primary and standby have committed it). Failover is automatic (no human required), in < 2 minutes, with zero data loss. The application connection string doesn't change — RDS handles the DNS flip transparently.

For a business that had three outages last quarter, Multi-AZ is the correct answer. Read Replicas can be added later for read scaling once the availability problem is solved.

**ADR-002 decision recorded:**  
> RDS Multi-AZ over single AZ. Cost: ~$60/month additional. Risk eliminated: total data tier unavailability. Three outages at $5,000 each = $15,000/quarter risk. Architecture pays for itself in the first prevented outage.

### Step 6 — CDN: CloudFront with PriceClass_200

```
Current:  No CDN — all requests reach EC2 in us-east-1
Designed: CloudFront distribution (PriceClass_200)

PriceClass options:
  PriceClass_100: US + Europe edge locations only
  PriceClass_200: US + Europe + Asia Pacific (Singapore, Tokyo, Sydney, Mumbai)
  PriceClass_All: All 450+ global edge locations

Client is APAC-focused → PriceClass_200 is required.

Request flow:
  Singapore user → CloudFront Singapore PoP (cached response: ~20ms)
  vs.
  Singapore user → us-east-1 origin (no CDN: ~180ms)
```

**Why PriceClass_200, not PriceClass_All?**

PriceClass_All includes South America, Middle East, and Africa edge locations. These regions have higher CloudFront data transfer costs (up to $0.17/GB vs $0.02/GB for US). The client's customer base is APAC — there is no business justification for paying premium edge pricing for regions with negligible traffic.

PriceClass_200 covers:
- Singapore, Tokyo, Sydney, Mumbai (core APAC)
- US East + West
- Europe (Frankfurt, London, Paris)

This covers 95% of the client's traffic at ~30% lower cost than PriceClass_All.

**CloudFront configuration:**
- **Cache TTL for static assets:** 1 year (`Cache-Control: max-age=31536000, immutable`) — CSS, JS, images with content-hashed filenames never change
- **Cache TTL for HTML:** 0 (`Cache-Control: no-cache`) — HTML references hashed asset filenames, must always be fresh
- **Origin:** Elastic Beanstalk ALB URL as the dynamic origin; S3 bucket for static assets via OAC
- **HTTPS:** ACM certificate, HTTP → HTTPS redirect at CloudFront

**ADR-003 decision recorded:**  
> PriceClass_200 over PriceClass_100. Rationale: APAC is the client's primary market. PriceClass_100 routes Singapore users to the nearest US/EU edge (18–20ms APAC-to-US latency becomes 180ms). PriceClass_200 adds ~$15/month but reduces APAC latency to ~20ms.

### Step 7 — Route 53 Latency-Based Routing

```
Route 53 Hosted Zone: nexacorp.example.com
  └── Latency record set
      ├── us-east-1: Beanstalk ALB endpoint (primary, covers US users)
      └── ap-southeast-1: Beanstalk environment (APAC, covers Singapore/SEA users)
```

Route 53 latency-based routing sends each user to the AWS region that will give them the lowest latency, based on periodic latency measurements AWS maintains between Route 53 PoPs and AWS regions.

**Why not just CloudFront for all traffic, including dynamic?**  
CloudFront caches responses. Dynamic content (personalized pages, user-specific data) cannot be cached — it must reach the origin. Route 53 latency-based routing ensures that a Singapore user's dynamic requests reach the ap-southeast-1 Beanstalk environment (deployed in a second region for APAC) rather than traversing to us-east-1.

For this client at their current scale, a single region with CloudFront is acceptable as Phase 1. Multi-region with Route 53 latency routing is Phase 2 when APAC revenue justifies the cost of maintaining a second environment.

### Step 8 — Monitoring: CloudWatch Alarms + SNS

```
CloudWatch Alarms:
  ├── EC2 CPU utilization > 80% for 5 minutes → SNS → Email/SMS to ops team
  ├── ALB HTTP 5xx error rate > 1% → SNS → urgent alert
  ├── RDS Connections > 80% of max_connections → SNS
  └── ALB TargetResponseTime p99 > 1000ms → SNS

All alarms → SNS Topic → Email + SMS to on-call rotation
```

**Why these 4 alarms specifically:**

- **CPU > 80%:** Leading indicator of compute saturation — alert before Auto Scaling is overwhelmed
- **5xx rate > 1%:** Lagging indicator of application failure — fires when users are already experiencing errors
- **RDS connections > 80%:** MySQL has a hard `max_connections` limit (based on instance memory). When this is hit, new connections fail — the application returns database connection errors. Alerting at 80% gives 20% headroom for investigation
- **ALB p99 latency > 1000ms:** User-facing SLA indicator. p99 > 1 second means 1% of users experience "broken" page loads. Correlates with bounce rate and revenue impact

---

## Stakeholder Communication Flow

### Step 9 — Architecture Presentation to Non-Technical Stakeholders

The challenge: present an AWS architecture with 6 services to a CEO and VP of Operations who have never used the AWS console.

**Technique: Layer the explanation**

1. Start with the problem statement they already agree with ("your site goes down under load")
2. Name the solution principle ("we're eliminating every single point of failure")
3. Explain each component using an analogy they already have
4. Show the before/after: one column for each architecture component, old vs. new

The restaurant analogy (used for Auto Scaling, above) worked because it maps to a mental model the VP of Operations (who came from a hospitality background) already had. The key insight: **the analogy doesn't need to be technically precise — it needs to transfer the concept accurately**.

"Auto Scaling is like an elastic workforce" is technically accurate but abstract. "Auto Scaling is like calling in more waitstaff when the dinner rush arrives" is slightly imprecise (the analogy doesn't cover instance warmup time or session stickiness) but transfers the concept of pay-per-use horizontal scaling perfectly.

### Step 10 — Handling the Cost Objection

The objection: "We're currently paying $70/month. This new architecture looks more expensive."

**The flawed SA response:** "The new architecture costs $280/month. Here's why each service is necessary..."  
This response defends the bill. It frames the conversation as cost vs. features.

**The correct SE response:**

> "Your current $70/month is paying for a system that's caused three outages in the past quarter. Each outage costs approximately $5,000 in lost revenue, customer support time, and customer trust. That's $15,000/quarter in risk for a $70/month architecture. The new architecture costs $280/month — about $250 more per month, or $3,000/year. A single prevented outage covers the entire year's cost difference. You're not paying more for the same architecture. You're buying downtime insurance."

**What made this work:**

1. **Acknowledged the objection directly:** "The new architecture is more expensive" — don't hedge
2. **Reframed the denominator:** Move from "cost per month" to "risk per quarter"
3. **Provided the client's own data:** Used the outage history they disclosed in discovery
4. **Made the math explicit:** $3,000/year vs $15,000/quarter risk — the math is unavoidable
5. **Named what they're buying:** Not "a load balancer" — "downtime insurance"

This is the difference between technical selling and business-value selling. Technical selling presents features. Business-value selling presents outcomes in the language the buyer cares about (revenue, risk, competitive position).

---

## AWS Well-Architected Framework Analysis

### Operational Excellence

- **Elastic Beanstalk managed updates:** AWS handles OS and runtime patching — removes toil from a 3-person ops team
- **`eb deploy` deployment:** Single command, health-check aware — rolls back automatically if new version fails health checks
- **CloudWatch alarms:** Proactive monitoring — ops team is alerted before users start calling
- **ADRs documented:** Every architecture decision recorded with rationale, enabling future SA to understand why Beanstalk was chosen and when to revisit (12-month trigger: team adds container expertise)

### Security

- **HTTPS via ACM:** TLS certificate managed and auto-renewed by ACM — no manual certificate rotation
- **Security groups:** ALB security group allows 443 from 0.0.0.0/0; EC2 security group allows 80/443 only from ALB security group; RDS security group allows 3306 only from EC2 security group. No public RDS access.
- **IMDSv2:** Beanstalk launch configuration sets `MetadataHttpTokens=required` — SSRF cannot steal EC2 credentials
- **RDS encryption at rest:** AES-256 (default for RDS) — database backups and storage encrypted

### Reliability

- **Multi-AZ compute:** Min 2 EC2 instances across 2 AZs — single instance failure is zero-downtime
- **RDS Multi-AZ:** Automatic failover in < 2 minutes, zero data loss — synchronous replication
- **ALB health checks:** Unhealthy instances removed from rotation within 30 seconds
- **CloudFront edge caching:** If the origin is temporarily unavailable, CloudFront serves cached static assets — partial functionality preserved during origin issues

### Performance Efficiency

- **CloudFront APAC edge:** Singapore/Tokyo PoPs serve APAC users at ~20ms vs 180ms from us-east-1
- **Auto Scaling target tracking:** CPU target tracking is more responsive than step scaling — scales smoothly with load rather than in discrete steps
- **RDS db.t3.medium:** Adequate for the client's current scale (burstable, 2 vCPU, 4GB RAM). The T3 family's CPU credit system handles short spikes without over-provisioning a fixed-size instance

### Cost Optimization

- **Auto Scaling pay-per-use:** 2 instances overnight, 8 instances during campaign peaks — no idle capacity
- **CloudFront PriceClass_200:** Not paying for South America and Middle East edge locations where the client has no users
- **RDS Reserved Instance:** After 1 year of stable usage, purchase a 1-year RI for the RDS instance — ~40% savings vs on-demand. Phase 2 recommendation after architecture proves stable

### Sustainability

- **Auto Scaling:** Instances terminate when demand drops — no idle EC2 running overnight
- **CloudFront caching:** Fewer origin requests = fewer EC2 compute cycles for static asset delivery

---

## Key Architectural Insight

The core lesson of this engagement is that **architecture is a client conversation, not a technical specification**. The "best" architecture (EKS, complex CI/CD, multi-region active-active) is irrelevant if the client's team cannot operate it. The right architecture is the one that:

1. Solves the stated problem (outages under load)
2. Matches the team's operational capability
3. Has a clear upgrade path (Beanstalk → ECS when the team adds container skills)
4. Can be explained in language the decision-maker understands

This is the Solutions Architect / Solutions Engineer distinction in practice: an SA can design any architecture. An SA/SE designs the right architecture for this client, at this moment, and can explain it in the client's language.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
