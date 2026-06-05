# Architecture Deep Dive — Highly Available WordPress on AWS
## Solutions Architect Analysis · AWS Well-Architected Framework

---

## Executive Summary

This document explains every architectural decision in the HA WordPress deployment — from the first DNS lookup a user makes to the last byte written to S3 logs. Each service is justified against alternatives. Every configuration choice has a reason. The Well-Architected Framework evaluation covers all six pillars.

**The core problem:** A single EC2 instance is not a production architecture. It is a prototype that works until it doesn't — and when it fails, it fails completely. This architecture eliminates every single point of failure across the DNS, CDN, compute, database, and storage layers simultaneously.

---

## Step 1 — User Request Enters the System: Route 53

### What happens
A user types `www.yourclient.com` in their browser. The browser performs a DNS lookup. That request hits **Amazon Route 53**.

### Why Route 53 (not a third-party DNS provider)
- Route 53 is an **anycast DNS service** — queries are answered from the nearest AWS edge location globally, not a single DNS server. Latency is typically under 10ms.
- Route 53 supports **health checks with DNS failover** — if the CloudFront distribution or origin becomes unhealthy, Route 53 can automatically redirect traffic to a static S3 maintenance page within 60 seconds.
- An **Alias record** (not a CNAME) points to CloudFront. Alias records are free (CNAMEs to AWS resources are charged per query), and they work at the zone apex (`yourclient.com`, not just `www.yourclient.com`).
- Route 53 is integrated with ACM for certificate validation — the `_acme-challenge` DNS record is created automatically.

### Configuration detail
```
A record (Alias) → CloudFront distribution domain
AAAA record (Alias) → CloudFront distribution domain (IPv6)
Health check → CloudFront URL, interval 30s, threshold 3 failures
```

**Why not:** GoDaddy DNS, Cloudflare Free — no native AWS health check integration, no Alias records, no seamless ACM validation.

---

## Step 2 — Traffic Hits the Edge: CloudFront + WAF

### What happens
Route 53 returns the CloudFront distribution's IP. The user's browser connects to the **nearest CloudFront edge location** (not the ALB or EC2 directly). CloudFront inspects the request against **AWS WAF** before deciding what to do with it.

### Why CloudFront
CloudFront is a **Content Delivery Network (CDN)** with 450+ edge locations globally. Its role here is threefold:

**1. Security perimeter:** The ALB (origin) is never exposed to the public internet directly. CloudFront sits in front of it. WAF rules execute at the edge — malicious requests are blocked before they consume any compute resources at origin.

**2. Static asset caching:** WordPress serves a mix of dynamic PHP pages and static assets (CSS, JS, images). CloudFront distinguishes between them:
- Static assets (`/wp-content/uploads/*`, `*.css`, `*.js`) → cached at edge for up to 1 year via `Cache-Control: max-age=31536000, immutable`
- Dynamic WordPress pages (PHP requests) → forwarded to ALB with `Cache-Control: no-store`

This means ~60-70% of requests for a typical WordPress site never reach the origin server.

**3. TLS termination:** CloudFront terminates TLS using the ACM certificate. The connection between CloudFront and the ALB uses a separate HTTPS connection (origin protocol HTTPS). The ALB certificate is a separate ACM certificate. End-to-end encryption: browser → CloudFront (TLS 1.3) → ALB (TLS 1.2+) → EC2.

### Why WAF on CloudFront (not on ALB)
WAF on CloudFront runs at the edge — an attack from Tokyo is blocked in Tokyo, not in us-east-1. This means:
- No bandwidth cost for blocked traffic (WAF blocks before CloudFront forwards)
- Blocked requests don't consume ALB capacity units
- Lower latency for legitimate users (edge doesn't need to forward bad traffic)

**WAF rule groups configured:**
1. `AWSManagedRulesCommonRuleSet` — OWASP Top 10 (XSS, SQLi, path traversal, etc.)
2. `AWSManagedRulesSQLiRuleSet` — Dedicated SQL injection protection (WordPress login pages are targeted)
3. `AWSManagedRulesKnownBadInputsRuleSet` — Log4j exploit patterns, SSRF patterns
4. **Custom rate-based rule:** 2,000 requests per 5 minutes per IP → block (prevents brute-force on `wp-login.php`)

**Why PriceClass_100 (not ALL):**
PriceClass_100 covers US, Canada, and Europe — the client's user base. PriceClass_ALL adds Asia Pacific, South America, and Africa edges for ~30% higher CloudFront cost. The decision is always: where are your users? Don't pay for edges in regions you don't serve.

---

## Step 3 — Dynamic Requests Reach Origin: Application Load Balancer

### What happens
CloudFront determines the request is dynamic (PHP). It forwards the request to the **Application Load Balancer (ALB)** over HTTPS.

### Why ALB (not NLB, not Classic ELB)
- **ALB operates at Layer 7 (HTTP/HTTPS).** It understands HTTP headers, paths, and methods. This allows path-based routing (e.g., `/wp-admin/*` → separate target group with stricter rules).
- **ALB performs health checks** at the application layer — it sends an HTTP GET to `/healthcheck.php` on each EC2 instance and checks for a 200 response. If an instance fails 3 consecutive checks (unhealthy threshold), traffic is drained and the instance is removed from rotation.
- **Connection draining (deregistration delay: 30 seconds):** When an instance is terminated (scale-in or failure), the ALB gives in-flight requests 30 seconds to complete before closing the connection. Zero dropped requests during scale events.
- **Access logging to S3:** Every request (IP, path, status, latency, user agent) is logged to S3 for security audit and debugging.
- **HTTP → HTTPS redirect:** A listener rule on port 80 returns a 301 to HTTPS. All traffic is encrypted.

### Why only HTTPS from CloudFront to ALB
Even though traffic is already encrypted from the user to CloudFront, the CloudFront → ALB hop should also be HTTPS. Reasons:
1. If someone discovers the ALB DNS name, they can bypass CloudFront and WAF entirely using HTTP
2. CloudFront-to-ALB traffic travels over AWS backbone networks, but the ALB DNS name is public
3. Security best practice: encrypt every hop

**ALB security group rule:** Only accepts HTTPS (443) from CloudFront managed prefix list — the ALB literally cannot receive traffic from any other source.

### Listener rules
```
Port 80  → Redirect to HTTPS (301)
Port 443 → Default → Forward to wordpress-target-group
Port 443 → Path /wp-admin/* → Forward to wordpress-target-group (same group, different rule for future WAF tuning)
```

---

## Step 4 — Compute Layer: EC2 Auto Scaling Group

### What happens
The ALB forwards the request to one of the EC2 instances in the **Auto Scaling Group (ASG)**. The instance runs WordPress PHP-FPM behind Nginx.

### Why EC2 ASG (not ECS Fargate, not Lambda)
**The WordPress constraint:** WordPress is a stateful PHP application. Its plugins assume:
- Writable filesystem (`/wp-content/uploads/`) for media uploads
- Plugin files stored locally
- Session state (though this can be externalized)

ECS Fargate containers are ephemeral — the filesystem disappears when the task stops. Moving WordPress to containers requires significant re-architecture (externalize uploads to EFS, sessions to Redis, plugin compatibility testing). That scope exceeded the project requirements.

EC2 ASG with **EFS for shared media** gives WordPress the stateful filesystem it expects while still supporting horizontal scaling across instances.

### Launch Template — every setting explained

```hcl
instance_type = "t3.medium"   # 2 vCPU, 4 GB RAM — right-sized for WordPress PHP-FPM
```
- **Why t3.medium:** WordPress with a caching plugin runs comfortably at 2 vCPU / 4 GB. t3 instances use burstable CPU — cost-efficient for workloads with moderate average CPU and occasional spikes.
- **Why not t3.micro:** PHP-FPM worker processes require ~256MB each. At 4 workers (minimum production), you need ~1 GB just for PHP. A t3.micro (1 GB total) leaves no headroom for Nginx, OS, and WordPress core.

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # IMDSv2 — blocks SSRF attacks
  http_put_response_hop_limit = 1
}
```
- **Why IMDSv2:** The Instance Metadata Service (IMDS) is accessible from any process on the EC2 instance at `169.254.169.254`. In 2019, the Capital One breach exploited SSRF to call IMDS and steal IAM credentials. IMDSv2 requires a session token to access metadata — a simple SSRF cannot obtain it. This is a non-negotiable security baseline.

```hcl
ebs_optimized = true
root_block_device {
  volume_type = "gp3"
  volume_size = 30
  encrypted   = true
  kms_key_id  = aws_kms_key.nexashop.arn
}
```
- **Why gp3 (not gp2):** gp3 provides 3,000 IOPS and 125 MB/s throughput at any volume size, for 20% less cost than gp2. gp2 only delivers 3 IOPS/GB — a 30 GB volume gives 90 IOPS. That is not enough for a production WordPress installation (plugin writes, WP-Cron, database queries).
- **Why encrypted EBS:** At-rest encryption protects data if someone physically removes the volume (unlikely in AWS, but compliance requirement). KMS CMK gives full audit trail (CloudTrail logs every KMS API call).

### Auto Scaling Policies — two policies, not one

**Policy 1: CPU Target Tracking (70%)**
```hcl
target_tracking_configuration {
  predefined_metric_specification {
    predefined_metric_type = "ASGAverageCPUUtilization"
  }
  target_value = 70.0
}
```
- Maintains average CPU across the group at 70%. If CPU exceeds 70%, the ASG adds instances. If it drops below, instances are removed (with a 5-minute cooldown to prevent thrashing).
- **Why 70% (not 80% or 50%):** 70% leaves a 30% buffer to absorb a sudden traffic spike while new instances are launching (typically 90-120 seconds for a cold instance). At 80%, a 50% traffic spike would push you to 144% CPU before scaling completes — requests would queue and time out. At 50%, you're over-provisioning significantly.

**Policy 2: ALB Request Count Per Target (1,000)**
```hcl
target_tracking_configuration {
  predefined_metric_specification {
    predefined_metric_type = "ALBRequestCountPerTarget"
    resource_label         = "${aws_alb.main.arn_suffix}/${aws_alb_target_group.wordpress.arn_suffix}"
  }
  target_value = 1000.0
}
```
- CPU alone misses the case where WordPress is slow (high response time, low CPU) due to database bottleneck. Request count per target catches "too many concurrent connections even if CPU is low."
- Two policies: ASG uses whichever requires more instances.

**Scheduled scaling:**
```hcl
scheduled_action {
  name             = "scale-out-business-hours"
  min_size         = 3
  desired_capacity = 4
  recurrence       = "0 8 * * MON-FRI"   # 8am weekdays
}
scheduled_action {
  name             = "scale-in-overnight"
  min_size         = 2
  desired_capacity = 2
  recurrence       = "0 20 * * *"         # 8pm every day
}
```
- **Why:** Predictable traffic patterns (office hours) should be handled proactively. Reactive scaling takes 90-120 seconds — scheduled scaling pre-provisions capacity before traffic arrives.
- **Cost impact:** Running 2 instances overnight instead of 4 saves ~$60/month.

### IAM Instance Profile — least privilege
The EC2 instances need to:
1. Read the database password from Secrets Manager
2. Write media uploads to S3
3. Pull WordPress code from CodeDeploy (if used)
4. Send logs to CloudWatch

The IAM role allows exactly these four things, scoped to specific resource ARNs. It cannot call any other AWS service. If the instance is compromised, the blast radius is limited to: read one secret, write to one S3 prefix, send logs.

---

## Step 5 — Shared Filesystem: Amazon EFS

### Why EFS
WordPress `wp-content/uploads/` must be writable by any EC2 instance in the ASG. If instance A handles an upload and writes the file locally, instance B will return a 404 for that image because the file doesn't exist on its local disk.

**EFS (Elastic File System)** is a managed NFS service. All EC2 instances mount the same EFS filesystem — uploads written by instance A are immediately visible to instance B.

**EFS lifecycle policy:** Files not accessed in 30 days automatically move to EFS-IA (Infrequent Access) storage — 92% cheaper than standard EFS. Old media files rarely accessed consume minimal cost.

**EFS mount target:** One mount target per AZ, in the private subnet. EFS traffic never leaves the VPC.

**Why not S3 for uploads directly:** WordPress and its plugins write to the local filesystem using PHP's `file_put_contents()`. Making this S3-aware requires a plugin (WP Offload Media) and configuration. EFS gives WordPress the filesystem it expects without requiring application changes.

---

## Step 6 — Database Layer: RDS MySQL Multi-AZ

### What happens
The WordPress application (running on EC2) needs to read and write to MySQL. It connects to the **RDS endpoint** — a DNS name that always points to the current primary instance.

### Why RDS (not self-managed MySQL on EC2)
- **Managed service:** No OS patching, no MySQL upgrade management, no replication configuration
- **Automatic backups:** Daily automated snapshots retained for 7 days. Point-in-Time Recovery to any second within the retention window
- **Multi-AZ:** Synchronous replication to a standby instance in a different AZ — automatic failover in under 2 minutes, no DNS change needed, no application reconnection required

### Multi-AZ — how it actually works
```
Primary RDS (us-east-1a)     Standby RDS (us-east-1b)
       │                              │
       │ Synchronous replication ────►│
       │ (every write confirmed       │
       │  on both before ACK)         │
       │                              │
WordPress writes to primary ─────────►│
Primary fails → RDS promotes standby  │
DNS endpoint flips to standby ────────┘
Application reconnects to same DNS name
```

**Why synchronous (not asynchronous):** Synchronous replication means every write is confirmed on BOTH instances before the application receives a success response. The standby is always 100% current. If the primary fails after acknowledging a write, the standby has that data. Asynchronous replication (like read replicas) has replication lag — failover can lose recent writes.

**Failover time:** < 2 minutes. This includes:
- RDS detecting primary failure (health check timeout: ~1 minute)
- Promoting standby (< 1 minute)
- DNS TTL expiry (60 seconds, but WordPress reconnects on next DB call)

### Why gp3 storage
Same reason as EBS: 3,000 IOPS at any size, 20% cheaper than gp2. A WordPress database doing 100 requests/second generates significant I/O. Underpowered storage causes MySQL query queuing.

### Secrets Manager integration
The MySQL password is stored in AWS Secrets Manager. EC2 instances fetch it via the Secrets Manager API at startup (not hardcoded in `wp-config.php`). Automatic rotation is configured — every 90 days, Secrets Manager generates a new password and updates both the RDS instance and the Secrets Manager secret. The EC2 instances fetch the new secret on next connection.

**Why not hardcode the password in `wp-config.php`:**
1. `wp-config.php` is often accidentally committed to version control
2. If EC2 is compromised and attacker reads the filesystem, they get the password
3. Rotation requires re-deploying the application

---

## Step 7 — Networking Foundation: VPC Design

### 3-Tier Subnet Architecture

```
VPC: 10.0.0.0/16 (65,536 addresses)

Public Subnets (ALB, NAT Gateways):
  10.0.1.0/24  — us-east-1a  (251 usable addresses)
  10.0.2.0/24  — us-east-1b
  10.0.3.0/24  — us-east-1c

Private Subnets (EC2 instances):
  10.0.11.0/24 — us-east-1a
  10.0.12.0/24 — us-east-1b
  10.0.13.0/24 — us-east-1c

Data Subnets (RDS, ElastiCache, EFS):
  10.0.21.0/24 — us-east-1a
  10.0.22.0/24 — us-east-1b
  10.0.23.0/24 — us-east-1c
```

### Why 3 tiers (not 2)

**Public tier:** Reachable from the internet. ALB nodes and NAT Gateways live here. Nothing else. EC2 instances are NOT in the public subnet — there is no reason for a web server to have a public IP.

**Private tier:** No public IPs, no inbound internet. EC2 instances live here. They can reach the internet via NAT Gateway (for OS updates, plugin downloads) but cannot be reached from the internet. If an attacker finds a vulnerability in WordPress, they cannot directly connect to the EC2 instance — they can only reach the ALB.

**Data tier:** No internet route at all. Not even a NAT Gateway. The only traffic that can reach the RDS instance is from the EC2 security group on port 3306. An attacker who compromises an EC2 instance still cannot exfiltrate the database over the internet — the data subnet has no outbound internet route.

### Why NAT Gateway per AZ (not one shared NAT)

```
AZ-1a fails:
  WITHOUT per-AZ NAT: EC2 in AZ-1b and AZ-1c lose internet (NAT was in AZ-1a)
  WITH per-AZ NAT:    EC2 in AZ-1b and AZ-1c use their own NAT — unaffected
```

One shared NAT Gateway is a **single point of failure**. Cost: ~$64/month for two additional NAT Gateways. At 99.9% SLO, this is mandatory.

### VPC Endpoints

**S3 Gateway Endpoint (free):** EC2-to-S3 traffic routes through the AWS backbone, not the internet. Without this, S3 traffic goes through the NAT Gateway, incurring data transfer charges. With the gateway endpoint: free, faster, more secure.

**Secrets Manager Interface Endpoint:** EC2 fetches secrets over a private interface within the VPC — not over the internet or through NAT. Required for environments where NAT is disabled or restricted.

### Security Groups — defense in depth

```
cloudfront-to-alb-sg:
  Inbound:  HTTPS (443) from CloudFront managed prefix list ONLY
  Outbound: All traffic

alb-to-ec2-sg:
  Inbound:  HTTPS (443) from cloudfront-to-alb-sg
  Outbound: All traffic

ec2-to-rds-sg:
  Inbound:  MySQL (3306) from alb-to-ec2-sg
  Outbound: All traffic

ec2-to-efs-sg:
  Inbound:  NFS (2049) from alb-to-ec2-sg
  Outbound: All traffic
```

Each security group references the previous tier's security group (not CIDR blocks). This means even if you know the IP ranges, you cannot bypass the chain. The ALB can only be reached from CloudFront. EC2 can only be reached from the ALB. RDS can only be reached from EC2.

---

## Step 8 — Encryption: KMS Customer Managed Key

### Why KMS CMK (not default AWS-managed keys)

A Customer Managed Key gives you:
1. **Key rotation control:** Automatic rotation every year (configurable)
2. **Audit trail:** Every KMS API call (Encrypt, Decrypt, GenerateDataKey) is logged in CloudTrail with the calling IAM principal
3. **Key policy:** You control who can use the key. The EC2 instance role can decrypt EBS and S3. The RDS service can use the key. Nothing else can.
4. **Key deletion control:** 7-30 day waiting period prevents accidental deletion

**What is encrypted:**
- EBS volumes (EC2 root and data volumes)
- RDS storage (MySQL data at rest)
- S3 media bucket (SSE-KMS)
- Secrets Manager secrets
- CloudWatch Logs (log groups)
- SNS topics (message bodies)

**The encryption chain:** Data written to EBS never leaves the EC2 host unencrypted. The AWS hypervisor handles the encryption/decryption transparently. There is no performance penalty for gp3 volumes with encryption.

---

## Step 9 — Observability: CloudWatch + SNS

### Alarms configured (and why each threshold)

| Alarm | Metric | Threshold | Why |
|-------|--------|-----------|-----|
| `high-5xx-rate` | ALB `HTTPCode_Target_5XX_Count` | > 10/min for 3 periods | 5xx = application errors. 10/min is ~1% of 1,000 req/min. Below this is noise; above is a real problem. |
| `high-latency-p99` | ALB `TargetResponseTime` p99 | > 3 seconds | WordPress pages should render in < 1s. 3s p99 means 1% of users wait > 3s — SLO breach. |
| `rds-cpu-high` | RDS `CPUUtilization` | > 80% for 10 min | MySQL CPU > 80% sustained means slow queries or missing indexes. Investigate before it becomes an outage. |
| `rds-connections-high` | RDS `DatabaseConnections` | > 80% of max_connections | MySQL has a max_connections limit. Approaching it causes "too many connections" errors. |
| `asg-cpu-high` | EC2 `CPUUtilization` (ASG) | > 85% for 5 min | The ASG scaling policy targets 70% CPU. If actual CPU hits 85% sustained, scaling is failing to keep up. |
| `disk-space-low` | CloudWatch Agent `disk_used_percent` | > 80% on `/` | EBS runs out of space silently — WordPress stops working with cryptic errors. Alert early. |

All alarms trigger an **SNS topic** → email notification. The SNS topic is encrypted with the KMS CMK (so the alarm notification body, which may contain metric values, is encrypted in transit).

### Why CloudWatch Logs Insights (not just raw logs)

CloudWatch Logs Insights allows SQL-like queries over log data:
```sql
-- Find all 5xx errors in the last hour grouped by path
fields @timestamp, request_uri, status, response_time
| filter status >= 500
| stats count() as error_count by request_uri
| sort error_count desc
| limit 20
```

This query answers "which WordPress URL is generating the most errors" in seconds — without downloading logs or running grep.

---

## AWS Well-Architected Framework Evaluation

### Pillar 1: Operational Excellence
- **Infrastructure as Code:** All 15 Terraform files across 6 modules. Every change is in version control, peer-reviewed, and reproducible.
- **Deployment automation:** Launch Template instance refresh deploys new AMIs with zero downtime — ASG replaces instances one at a time, waiting for health checks before terminating old ones.
- **Runbooks:** Documented procedures for high CPU, RDS failover, WAF false positive — on-call knows what to do before the alert fires.
- **Improvement opportunity:** No automated runbook execution (AWS Systems Manager Automation). Manual response is acceptable at this scale.

### Pillar 2: Security
- **WAF at edge:** OWASP Top 10 + rate limiting before any traffic reaches compute
- **No public EC2 IPs:** EC2 lives in private subnets, unreachable from internet
- **IMDSv2:** Blocks SSRF-based metadata credential theft
- **Least-privilege IAM:** EC2 role grants minimum required permissions
- **Encryption everywhere:** KMS CMK for EBS, RDS, S3, Secrets Manager, SNS
- **No bastion host:** SSM Session Manager provides shell access without opening SSH port
- **Secret rotation:** Secrets Manager rotates MySQL password every 90 days automatically

### Pillar 3: Reliability
- **Multi-AZ at every layer:** ALB spans 3 AZs, ASG spans 3 AZs, RDS Multi-AZ, EFS multi-AZ
- **Health checks:** ALB health checks remove unhealthy instances from rotation
- **Auto Scaling:** Responds to CPU spikes within 90-120 seconds
- **RDS automatic failover:** < 2 minutes, no DNS change, no manual intervention
- **AWS Backup:** Daily snapshots of RDS, EFS, and EC2 EBS volumes retained for 30 days
- **CloudFront:** Continues serving cached content even if origin is temporarily unavailable

### Pillar 4: Performance Efficiency
- **CloudFront caching:** 60-70% of requests served from cache — origin sees only dynamic traffic
- **gp3 EBS and RDS storage:** 3,000 IOPS baseline, independent of volume size
- **Target tracking scaling:** CPU maintained at 70% — never under-provisioned or wastefully over-provisioned
- **EFS lifecycle:** Infrequently accessed media migrates to EFS-IA automatically

### Pillar 5: Cost Optimization
- **CloudFront PriceClass_100:** Pay only for edges that serve your users
- **Scheduled scaling:** 2 instances overnight, 4 during business hours — $60/month saved
- **gp3 over gp2:** 20% cheaper for same or better IOPS
- **S3 lifecycle:** STANDARD → STANDARD_IA (90d) → GLACIER (365d) — old media costs fractions of a cent
- **NAT Gateway consolidation consideration:** Per-AZ NAT adds $64/month — accepted for reliability. At very high data transfer volumes, consider AWS PrivateLink for specific services.

### Pillar 6: Sustainability
- **Right-sizing:** t3.medium instances are the minimum viable size — not over-provisioned by default
- **Auto scaling down:** Instances terminated during off-peak hours — no idle compute
- **CloudFront caching:** Fewer origin requests = less compute = lower energy per user request

---

## End-to-End Request Flow Summary

```
1. User browser → DNS lookup → Route 53 returns CloudFront IP
2. User browser → HTTPS request → CloudFront edge (nearest location)
3. CloudFront → WAF inspection → Block (malicious) OR Continue (legitimate)
4. CloudFront → Cache check → HIT (return cached response) OR MISS (forward to origin)
5. CloudFront → HTTPS → ALB (in public subnet, port 443)
6. ALB → Health check passes → Forward to EC2 instance (in private subnet)
7. EC2 (Nginx → PHP-FPM) → Read /wp-config.php → Fetch DB password from Secrets Manager
8. EC2 (WordPress) → MySQL query → RDS primary (in data subnet, port 3306)
9. RDS primary → Synchronous replication → RDS standby (different AZ)
10. RDS → Query result → WordPress PHP → HTML rendered
11. WordPress → File read (media) → EFS mount (shared across all EC2 instances)
12. EC2 → HTTP response → ALB → CloudFront → User browser
13. CloudFront → Cache static assets for future requests
14. ALB → Access log → S3 (for security audit)
15. CloudWatch Agent → EC2 metrics → CloudWatch → Alarm → SNS → Email alert
```

Total steps: 15. Every step is encrypted, logged, and resilient to failure.

---

*Vanessa Awo · Solutions Architect · [linkedin.com/in/vanessajen](https://linkedin.com/in/vanessajen) · [jenellavan.com](https://jenellavan.com)*
