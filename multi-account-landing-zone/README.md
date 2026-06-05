# Multi-Account AWS Landing Zone — Terraform

> **Architect:** Vanessa Awo · AWS Solutions Architect Associate  
> **Stack:** AWS Organizations · Control Tower · IAM Identity Center · Service Control Policies · Transit Gateway · Terraform  
> **Status:** Architecture designed + SCP code implemented ✅ | Multi-account governance ✅

---

## Problem Statement

NexaCorp (SA simulation) needed to support 12 teams across 3 business units with strict security and compliance requirements:
- **Blast-radius containment:** A security incident in the dev account must not affect production
- **Compliance:** Financial data must stay in approved regions, root user access disabled everywhere
- **Least privilege at scale:** Teams get only what they need, governed by policy-as-code
- **Cost visibility:** Each team/project tracked separately, hard budget limits enforced

**Goal:** Design and implement an AWS multi-account landing zone using AWS Organizations + Control Tower, with Terraform-managed SCPs and centralized identity.

---

## Account Structure

```
Management (Root) Account
├── Security OU
│   ├── Log Archive Account        (all org CloudTrail + Config logs)
│   └── Security Tooling Account  (GuardDuty aggregator, Security Hub, Macie)
│
├── Infrastructure OU
│   ├── Network Hub Account        (Transit Gateway, Direct Connect, DNS)
│   └── Shared Services Account   (ECR, Artifactory, internal tooling)
│
├── Workloads OU
│   ├── Production OU
│   │   ├── nexacorp-prod-payments
│   │   ├── nexacorp-prod-catalog
│   │   └── nexacorp-prod-auth
│   └── Non-Production OU
│       ├── nexacorp-dev
│       ├── nexacorp-staging
│       └── nexacorp-sandbox
│
└── Suspended OU
    └── (closed accounts awaiting deletion)
```

---

## Service Control Policies (Guardrails)

SCPs are applied at the OU level and inherited by all accounts. They cannot be bypassed even by account administrators.

| SCP Name | Applied To | What It Does |
|----------|-----------|-------------|
| `DenyRootUserActions` | Root (all accounts) | Root user cannot make any API call |
| `DenyLeaveOrganization` | Root (all accounts) | Accounts cannot remove themselves from Org |
| `ProtectCloudTrail` | Root (all accounts) | No one can disable org-level CloudTrail |
| `DenyPublicS3Buckets` | Root (all accounts) | Block public S3 ACLs and disable S3 Block Public Access override |
| `AllowedRegionsOnly` | Workloads OU | Only us-east-1 and us-west-2 allowed (global services exempted) |
| `RequireIMDSv2` | Workloads OU | EC2 launch denied if IMDSv1 enabled (SSRF protection) |
| `DenyNonApprovedInstanceTypes` | Production OU | Only approved EC2 sizes, no p4d.24xlarge etc. |
| `RequireTagsOnResources` | Workloads OU | Resources missing Project/Environment tags are denied |

---

## Identity Federation with IAM Identity Center

```
Identity Provider (Okta/Azure AD)
        │ SAML 2.0 / SCIM
        ▼
  IAM Identity Center (SSO)
        │
        ├── Permission Set: AdministratorAccess  → Security team → Security Tooling Account
        ├── Permission Set: ReadOnlyAccess        → Auditors     → All accounts
        ├── Permission Set: DeveloperAccess       → Dev teams    → Dev/Staging accounts
        ├── Permission Set: PowerUserAccess       → Leads        → Prod accounts (read only by default)
        └── Permission Set: BillingReadOnly       → Finance      → Management Account
```

**Key SSO design decisions:**
- No IAM users created in any account — all access via Identity Center
- MFA enforced for all Identity Center users via IdP policy
- Session duration: 8h for prod, 12h for non-prod
- Break-glass emergency access: separate IAM user in management account, credentials in sealed envelope

---

## Network Architecture (Hub-and-Spoke)

```
                    ┌─────────────────────────────────────────────┐
                    │           Network Hub Account                │
                    │                                             │
On-premises ────►  Direct Connect (10 Gbps)                      │
                    │        │                                    │
                    │   Transit Gateway ◄───────────────────────┐ │
                    │        │                                  │ │
                    └────────┼──────────────────────────────────┼─┘
                             │ TGW Attachments (one per account)│
               ┌─────────────┼──────────────────────┬───────────┘
               │             │                      │
     ┌─────────▼──┐  ┌───────▼──────┐  ┌───────────▼──────┐
     │  Prod VPC  │  │  Dev VPC     │  │  Shared Svc VPC  │
     │10.1.0.0/16 │  │10.2.0.0/16   │  │10.0.0.0/16       │
     └────────────┘  └──────────────┘  └──────────────────┘

TGW Route Tables:
  Prod RT:    allows Prod ↔ SharedSvc, blocks Prod ↔ Dev
  Dev RT:     allows Dev ↔ SharedSvc, blocks Dev ↔ Prod
  Shared RT:  allows → all accounts (one-way allowed)
```

**Transit Gateway design:**
- Centralized routing in Network Hub account — no peering mesh
- Route tables enforce Prod/Dev isolation — even at network layer
- Shared Services VPC (ECR, internal DNS, Artifactory) reachable from all accounts
- Direct Connect in hub account, shared via TGW to all workload accounts

---

## Centralized Logging & Security

```
All Accounts ──► CloudTrail (org trail) ──► Log Archive S3 Bucket
                                              (lifecycle: Glacier 90d)

All Accounts ──► AWS Config (org aggregator) ──► Security Hub aggregation

Security Hub aggregator (Security Tooling account):
  ├── CIS AWS Foundations Benchmark — automated compliance checks
  ├── AWS Foundational Security Best Practices
  ├── GuardDuty findings (all accounts aggregated)
  └── Macie findings (S3 data classification)
```

---

## Cost Governance

```
Management Account
├── AWS Budgets
│   ├── Org total: $10,000/month alert at 80% + 100%
│   ├── Per-account budgets (each account has individual limit)
│   └── Per-service anomaly detection
│
└── Cost Allocation Tags enforced via SCP:
    Project, Environment, Owner, CostCenter
    (Resources without these tags → denied by SCP)
```

---

## Key Architecture Decisions

### Why AWS Organizations over separate accounts with peering?
- VPC peering doesn't scale (N×(N-1)/2 connections), doesn't share DNS, can't centralize logging
- Organizations enables SCPs (cannot be overridden), centralized billing, org-level CloudTrail
- Control Tower provides pre-built guardrails and account vending machine

### Why Transit Gateway instead of VPC peering?
- TGW = hub-and-spoke, scales to 5000 VPC attachments
- Route tables in TGW enforce Prod↔Dev isolation at the network layer
- Single Direct Connect shared to all accounts via TGW — no per-account DX circuits

### Why IAM Identity Center instead of cross-account IAM roles?
- Users get a single login for all accounts — no juggling roles or credentials
- Centralizes MFA enforcement, session policies, and audit logs
- Integrates with existing IdPs (Okta, Azure AD) via SAML 2.0

### Why Log Archive as a separate account?
- Security accounts cannot delete their own logs (SCP + bucket policy denies it)
- Even if a production account is compromised, logs are in a separate blast radius
- Regulatory requirement: audit logs must be tamper-proof

---

## Skills Demonstrated

- **Multi-account governance:** AWS Organizations, OUs, SCPs, Control Tower
- **Network architecture at scale:** Transit Gateway hub-and-spoke, route table isolation
- **Identity management:** IAM Identity Center (SSO), SAML federation, permission sets
- **Security at the organization level:** GuardDuty aggregation, Security Hub, centralized CloudTrail
- **Policy as code:** 8 SCPs covering root user, regions, IMDSv2, public S3, CloudTrail protection
- **Cost governance:** AWS Budgets, mandatory cost allocation tags enforced by SCP
- **Blast radius design:** Prod/Dev network isolation, separate log archive, suspended OU

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
