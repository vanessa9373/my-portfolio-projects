# Multi-Account Landing Zone — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** End-to-end governance flow — from developer login to workload deployment to security audit

---

## What This Architecture Solves

A single AWS account for a 12-team organization means one compromise or one misconfiguration can affect every team's workload simultaneously. There is no blast radius containment, no way to enforce regional compliance per team, and no audit trail separation. A Landing Zone is the answer — it governs what teams can do before they even open the console.

---

## Account Structure Decision: Why 4 OUs, Not 1 Account

The first architectural decision is whether to use a single account with IAM isolation or multiple accounts.

**Single-account problems:**
- IAM cannot prevent a team from describing another team's RDS instances in the same account
- A misconfigured S3 bucket policy can expose data from adjacent teams
- Billing is aggregated — impossible to attribute costs per team
- A compromised IAM credential in the dev environment has the same account boundaries as production

**Multi-account with Organizations:**
- Each account is a hard blast-radius boundary — account-level IAM, VPCs, and billing are fully isolated
- SCPs at the OU level override even account-level administrator permissions
- Organizational CloudTrail captures every API call across all accounts into a single tamper-resistant log
- AWS Budgets per account enforces financial guardrails at the infrastructure layer

**The OU structure chosen:**

```
Root (Management)
├── Security OU          ← security tooling, never runs workloads
│   ├── Log Archive      ← all org CloudTrail + Config logs, write-once
│   └── Security Tooling ← GuardDuty aggregator, Security Hub, Macie
│
├── Infrastructure OU    ← shared networking and services
│   ├── Network Hub      ← Transit Gateway, Direct Connect, DNS
│   └── Shared Services  ← ECR, Artifactory, internal tooling
│
├── Workloads OU
│   ├── Production OU    ← stricter SCPs, tighter IAM, change management
│   └── Non-Production   ← developer-friendly, sandbox accounts
│
└── Suspended OU         ← closed accounts awaiting deletion, zero permissions
```

**Why separate Production and Non-Production OUs inside Workloads?** Different SCP sets apply. Non-prod allows any EC2 instance type for cost experimentation; prod restricts to an approved list. Non-prod allows 12-hour SSO sessions; prod enforces 8-hour sessions with MFA. Having two child OUs under Workloads lets you enforce these differences via SCP inheritance without maintaining separate policy sets for each account.

---

## Step-by-Step: Developer Login to Production Deploy

### Step 1 — Developer Opens AWS SSO Portal

Developer navigates to the IAM Identity Center access portal URL (e.g., `d-xxxx.awsapps.com/start`).

**Why IAM Identity Center instead of IAM users:**
- IAM users require per-account creation, per-user access keys, and manual rotation
- At 12 teams × 10+ accounts = 120+ IAM users to manage, rotate, and audit
- Identity Center federates an existing IdP (Okta, Azure AD) via SAML 2.0 — users log in with their corporate SSO credentials they already know
- MFA is enforced at the IdP layer — one policy covers all accounts simultaneously

### Step 2 — SAML 2.0 Authentication Flow

```
Developer browser ──► Identity Center portal
                            │ Redirect to IdP
                       Okta/Azure AD
                            │ User authenticates + MFA
                            │ SAML assertion returned
                       Identity Center
                            │ Maps SAML attributes to Permission Sets
                            ▼
                     Temporary credentials
                     (STS AssumeRoleWithSAML)
```

Identity Center receives the SAML assertion, determines which accounts and permission sets the user is entitled to, and calls `sts:AssumeRoleWithSAML` to generate temporary credentials (max 12h, configurable per permission set). The developer never sees a long-lived access key.

**Why SAML 2.0 not OIDC for SSO here:** AWS IAM Identity Center supports both, but SAML 2.0 is the enterprise standard for connecting to Okta/Azure AD and is the identity protocol most organizations already have configured. OIDC is better for machine-to-machine (e.g., GitHub Actions OIDC), not for human login flows integrated with corporate directory services.

### Step 3 — Permission Set Assignment Determines Scope

The permission set assigned to the user controls what they can do in which account:

| Permission Set | Who Gets It | What It Allows |
|---------------|-------------|----------------|
| `AdministratorAccess` | Security team | Full access — only in Security Tooling account |
| `DeveloperAccess` | Dev engineers | EC2, Lambda, S3, RDS — only in dev/staging accounts |
| `PowerUserAccess` | Team leads | All services — only in prod accounts, for break-glass |
| `ReadOnlyAccess` | Auditors | Describe/List/Get everywhere — all accounts |
| `BillingReadOnly` | Finance | Cost Explorer, Billing Console — management account only |

Permission sets are Terraform-managed. Adding a new developer = one Terraform resource. Revoking access = one `terraform destroy` targeting that assignment.

### Step 4 — SCP Layer: The Unbreakable Guardrail

Before the developer's API call reaches any AWS service, Service Control Policies evaluate it. SCPs operate at the Organizations level — they cannot be overridden by account-level IAM policies, even by an account administrator.

**How SCPs work architecturally:**

A request is allowed only if:
1. The SCP allows it (explicit allow or no explicit deny in any SCP in the path from root to the account's OU)
2. The IAM policy allows it

SCPs are NOT grants — they define the maximum permissions an IAM policy can grant. If the SCP at the root OU says `Deny ec2:RunInstances if IMDSv1`, an account-level IAM Administrator cannot override this.

**The 8 SCPs and why each exists:**

**`DenyRootUserActions`** (applied: Root)
```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "*",
  "Condition": { "StringLike": { "aws:PrincipalArn": "arn:aws:iam::*:root" } }
}
```
The root user is a permanent credential that cannot be restricted by IAM policies. It is exempt from all permission boundaries and service control policies except SCPs at the root OU. This SCP ensures no workload, no automation, and no human ever uses root. Only break-glass emergency access is exempt, and that is handled in the management account (which is not under this SCP's OU scope).

**`DenyLeaveOrganization`** (applied: Root)
Prevents any account from calling `organizations:LeaveOrganization`. Without this, a compromised account could remove itself from the organization, escaping all SCPs and centralized logging simultaneously. Once outside the org, the CloudTrail org trail stops capturing events for that account.

**`ProtectCloudTrail`** (applied: Root)
```json
{
  "Effect": "Deny",
  "Action": [
    "cloudtrail:DeleteTrail",
    "cloudtrail:StopLogging",
    "cloudtrail:UpdateTrail"
  ]
}
```
Organizational CloudTrail delivers logs to the Log Archive account. If an attacker compromises a workload account and tries to stop logging to cover their tracks, this SCP blocks it. An attacker who cannot erase their trail is an attacker who can be detected.

**`DenyPublicS3Buckets`** (applied: Root)
Blocks `s3:PutBucketAcl` with public ACLs and `s3:PutBucketPublicAccessBlock` with Block Public Access disabled. AWS S3 has shipped with safe defaults (Block Public Access enabled by default) since 2023, but this SCP makes it impossible to override — even if a developer accidentally has IAM permissions to do so.

**`AllowedRegionsOnly`** (applied: Workloads OU)
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Condition": {
    "StringNotEquals": { "aws:RequestedRegion": ["us-east-1", "us-west-2"] },
    "StringNotLike": { "aws:PrincipalArn": "arn:aws:iam::*:role/OrganizationAccountAccessRole" }
  }
}
```
Compliance requires financial data to reside only in approved US regions. Without this SCP, a developer could accidentally deploy an RDS instance in ap-southeast-1 (which violates the compliance boundary). The SCP exempts global services (IAM, Route 53, CloudFront — these use `us-east-1` as their API endpoint but are truly global). The exemption for `OrganizationAccountAccessRole` allows Control Tower vending to work.

**`RequireIMDSv2`** (applied: Workloads OU)
```json
{
  "Effect": "Deny",
  "Action": "ec2:RunInstances",
  "Condition": {
    "StringNotEquals": { "ec2:MetadataHttpTokens": "required" }
  }
}
```
IMDSv1 is a SSRF (Server-Side Request Forgery) vector. An attacker who finds an SSRF vulnerability in an application can call `http://169.254.169.254/latest/meta-data/iam/security-credentials/` and steal the instance role's temporary credentials. IMDSv2 requires a PUT pre-request with a TTL, making the token non-forwarding and blocking the SSRF vector. This SCP prevents any EC2 from being launched with IMDSv1 enabled — if the launch template doesn't set `MetadataHttpTokens=required`, the launch is denied.

**`DenyNonApprovedInstanceTypes`** (applied: Production OU)
Prevents launching GPU instances (p4d, p3, g4) or memory-optimized instances (x1e, high-memory) that have no place in production application workloads. This is a cost governance guardrail — a misconfigured autoscaling group targeting an expensive instance type cannot launch in production.

**`RequireTagsOnResources`** (applied: Workloads OU)
Any EC2 instance, RDS database, or Lambda function created without `Project` and `Environment` tags is denied. This enforces cost attribution at the infrastructure layer — finance can run a Cost Explorer report filtered by these tags and get exact per-project spend. No tag = no resource.

### Step 5 — Request Lands in the Workload Account

With credentials from Step 3 and guardrails from Step 4, the developer's Terraform or console action creates resources in the assigned account.

**Account vending (Control Tower Account Factory):**

New accounts are provisioned via Control Tower's Account Factory, which:
1. Creates the AWS account under the correct OU
2. Deploys the standard Landing Zone baseline (CloudTrail, Config, GuardDuty) via CloudFormation StackSets
3. Applies the correct SCP assignments for the target OU
4. Creates the `OrganizationAccountAccessRole` for cross-account management
5. Notifies the requester with account ID and console link

**Why CloudFormation StackSets for baseline, not Terraform?**  
StackSets are a native Organizations feature that can target every account in an OU simultaneously and update them all when the baseline changes. Terraform state management across 10+ accounts requires a state backend per account or a complex remote state architecture. For guardrail baselines (CloudTrail, Config, GuardDuty), StackSets are operationally simpler.

---

## Network Path: On-Premises to Production Workload

### Step 6 — Network Hub Account and Transit Gateway

All network connectivity flows through the Network Hub account. No VPC-to-VPC peering exists between workload accounts.

```
On-premises data center
        │
   AWS Direct Connect (10 Gbps dedicated circuit)
        │ Private VIF
   Direct Connect Gateway
        │
   Transit Gateway (Network Hub Account)
        │
        ├── TGW Attachment: Prod VPC (10.1.0.0/16)
        ├── TGW Attachment: Dev VPC (10.2.0.0/16)
        ├── TGW Attachment: Staging VPC (10.3.0.0/16)
        └── TGW Attachment: Shared Services VPC (10.0.0.0/16)
```

**Why Transit Gateway instead of VPC peering:**
- VPC peering is non-transitive: Prod can peer with SharedSvc, Dev can peer with SharedSvc, but Prod cannot reach Dev through SharedSvc. With 10 accounts, a peering mesh = 45 individual peer connections to manage
- TGW is transitive by design — every attachment can route to every other attachment (unless blocked by route tables)
- One Direct Connect circuit in the hub account, shared to all attachments via TGW — no per-account DX circuits
- TGW route tables enforce Prod/Dev isolation in a single configuration file

**TGW Route Table design:**

```
Production Route Table:
  Routes: 10.1.0.0/16 (self), 10.0.0.0/16 (SharedSvc), 192.168.0.0/16 (on-prem)
  NOT included: 10.2.0.0/16 (Dev), 10.3.0.0/16 (Staging)

Dev/Staging Route Table:
  Routes: 10.2.0.0/16 (Dev), 10.3.0.0/16 (Staging), 10.0.0.0/16 (SharedSvc)
  NOT included: 10.1.0.0/16 (Prod)

Shared Services Route Table:
  Routes: 10.0.0.0/16 (self), propagates to ALL attachments
```

The result: Dev can reach SharedSvc (to pull ECR images, use internal DNS), but a packet from Dev cannot reach Prod — the route doesn't exist in the TGW route table. This is network-layer isolation, not just IAM-layer isolation.

### Step 7 — Centralized DNS Resolution

Route 53 Resolver endpoints in the Shared Services VPC serve all workload accounts:

```
Workload VPC (10.1.x.x)
    │ DNS query for *.internal.nexacorp.com
    └── Resolver outbound endpoint ──► Shared Services Resolver inbound endpoint
                                              │
                                    Route 53 Private Hosted Zone
                                    (*.internal.nexacorp.com → correct resource IPs)
```

Every workload account has a Route 53 Resolver rule that forwards `*.internal.nexacorp.com` queries to the Shared Services account's resolver endpoint. This provides centralized DNS for all internal services without per-account hosted zones.

---

## Security and Observability Flow

### Step 8 — Every API Call Goes to Log Archive

The organizational CloudTrail trail delivers to the Log Archive account:

```
Any AWS Account (any API call)
        │
   CloudTrail (org trail, enabled by default for all accounts)
        │ S3 delivery (compressed JSON)
   Log Archive Account S3 Bucket
        │ S3 Object Lock (WORM — Write Once, Read Many)
        │ Lifecycle: IA after 30d → Glacier after 90d → Glacier Deep Archive after 365d
```

**Why S3 Object Lock (WORM mode)?**  
Even if an attacker compromises the Log Archive account, they cannot delete or overwrite objects with Object Lock enabled. SOC 2 and PCI-DSS require tamper-proof audit logs. WORM mode satisfies this at the storage layer, independent of IAM.

**Why Glacier for long-term retention?**  
Compliance requires 1-year CloudTrail retention for SOC 2. Active S3 storage for 365 days of org-level CloudTrail (across 10+ accounts) would cost ~$300/month. Glacier Deep Archive is $0.00099/GB — a 95% cost reduction. Retrieval for audit purposes (12-48h Glacier Deep Archive retrieval) is acceptable for compliance use cases.

### Step 9 — GuardDuty Aggregation in Security Tooling Account

```
GuardDuty enabled in every account (org auto-enable)
        │ Findings
GuardDuty Delegated Administrator (Security Tooling Account)
        │
Security Hub (also in Security Tooling Account)
        │ CIS AWS Foundations Benchmark
        │ AWS Foundational Security Best Practices
        │ Macie findings (S3 data classification)
        ▼
SNS Topic ──► PagerDuty/OpsGenie ──► On-call engineer
```

**Why a delegated administrator account?**  
If GuardDuty aggregation lived in the management account, security tooling and billing are co-located. The management account has elevated trust — it should do as little as possible. Delegating GuardDuty and Security Hub to a dedicated Security Tooling account follows the principle of least privilege at the account level.

**GuardDuty threat detection for multi-account environments:**

GuardDuty analyzes:
- VPC Flow Logs (unusual outbound connections, port scanning)
- CloudTrail (unusual API patterns, credential exfiltration behaviors)
- DNS logs (domains associated with command-and-control infrastructure)
- EKS audit logs (if Kubernetes workloads exist)
- S3 data events (unusual GetObject from anomalous IPs)

When a finding is generated in any member account, it surfaces in the Security Tooling account's GuardDuty console within minutes. High-severity findings trigger SNS → PagerDuty.

### Step 10 — Config Compliance Continuous Evaluation

AWS Config rules run continuously in every account:

```
Resource created/modified in any account
        │
AWS Config (per account, org aggregator in Security Tooling)
        │ Evaluates rules:
        ├── restricted-ssh: Security groups must not allow SSH from 0.0.0.0/0
        ├── s3-bucket-ssl-requests-only: S3 buckets must require SSL
        ├── rds-instance-public-access-check: RDS instances must not be public
        ├── encrypted-volumes: EBS volumes must be encrypted
        └── iam-password-policy: Password policy must meet minimum requirements
        │
Non-compliant → SNS ──► Security team Slack channel
Compliant → Recorded in Config history (6-year retention)
```

**Config vs CloudTrail:** CloudTrail is a *who did what* log (API calls). Config is a *what does it look like now* log (configuration state over time). Config answers: "Was this security group open at 2am on March 3rd?" CloudTrail answers: "Who opened it?" Both are required for full audit capability.

---

## Cost Governance Flow

### Step 11 — Tag Enforcement at Resource Creation

The `RequireTagsOnResources` SCP at the Workloads OU level means:
- Developer runs `terraform apply` without `Project` and `Environment` tags on an EC2 instance
- The `ec2:RunInstances` API call is evaluated by the SCP
- The condition checks for tag presence
- The call is denied with `AccessDenied` — the resource is never created

This is preventative, not detective. The developer knows immediately (at apply time) rather than discovering a compliance violation in a weekly report.

### Step 12 — AWS Budgets Alerting Chain

```
Management Account → AWS Budgets
    ├── Org total: alert at $8,000 (80%), hard limit notification at $10,000 (100%)
    ├── nexacorp-prod-payments: alert at $1,500/month
    ├── nexacorp-dev: alert at $500/month (sandbox spending cap)
    └── Per-service anomaly detection: alert if service spend increases >20% week-over-week

Alert triggers → SNS Topic → Lambda (optional cost attribution report) → Slack / Email
```

AWS Budgets anomaly detection uses machine learning on historical spend. If a developer accidentally enables CloudTrail data events for a high-traffic S3 bucket (which can generate millions of billable events/day), the anomaly detection triggers within hours — before the monthly bill doubles.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence

- **Infrastructure as code:** All SCPs, permission sets, and account assignments are Terraform-managed. `terraform plan` shows exactly what governance changes before applying
- **Account vending:** New accounts provisioned in < 30 minutes via Control Tower Account Factory — no manual console steps
- **Runbooks:** Break-glass emergency access procedure documented (sealed credentials, CloudTrail evidence required)
- **Drift detection:** AWS Config detects configuration drift from baseline and alerts within minutes

### Security

- **Root user disabled via SCP:** No workload can use root credentials
- **IMDSv2 enforced:** SSRF attacks cannot steal EC2 credentials across the entire organization
- **No long-lived credentials:** IAM Identity Center + temporary STS credentials only
- **Centralized logging in separate blast radius:** Log Archive account logs cannot be deleted even by a compromised workload account
- **GuardDuty + Security Hub:** Threat detection across all accounts, findings in one place
- **SCPs as preventative controls:** Policy violations are blocked, not just detected

### Reliability

- **No SPOF in identity:** If the IdP has a service disruption, break-glass IAM users exist in the management account
- **Transit Gateway across multiple AZs:** Each TGW attachment uses all AZs in the region — a single AZ failure doesn't disconnect the spoke VPC
- **Config continuous compliance:** Drift from reliable configurations is detected immediately

### Performance Efficiency

- **Transit Gateway for low-latency routing:** Workloads reach Shared Services (ECR, internal DNS) via TGW in the same region — no internet routing
- **Route 53 Resolver rules:** Internal DNS resolution is local to each VPC, forwarding only for internal domains — no DNS latency on public DNS

### Cost Optimization

- **Consolidated billing:** All accounts under one organization → volume discounts, AWS Enterprise Discount Program eligibility
- **Per-account budgets:** Prevents runaway spend in any single account
- **CloudTrail in Glacier after 90 days:** 95% cheaper than active storage for compliance-required long retention
- **Mandatory cost tags:** 100% of resource spend attributable to project/team — no "unknown" cost in Cost Explorer

### Sustainability

- **Right-sizing enforcement via SCP:** Prevents over-provisioned instance types in production
- **Automated account decommission:** Suspended OU with SCPs that deny all actions — zombie accounts use no resources

---

## Key Architectural Insight

The core principle of this Landing Zone is **defense in depth at the organizational layer**. Each control is independent:

1. **SCP** blocks the action at the API call level (before IAM is even evaluated)
2. **IAM** restricts what the identity can do even if SCP allows it
3. **Config** detects if something was misconfigured after creation
4. **GuardDuty** detects if a misconfiguration is being exploited
5. **CloudTrail** records the forensic trail

An attacker who bypasses one layer (compromises an IAM credential) still faces SCPs that limit what they can do, Config that detects anomalous resources they create, and GuardDuty that detects anomalous API patterns in real time.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
