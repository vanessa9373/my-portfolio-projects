# Lab 12: Automated Incident Response & Postmortem Pipeline — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + Google SRE Incident Management  
> **Scope:** Lambda-based automation pipeline — PagerDuty → Slack channel creation → Jira ticketing → auto-remediation → postmortem generation

---

## What This Pipeline Solves

Manual incident response has a compound problem: the first five minutes of any incident are spent on logistics rather than diagnosis. Someone notices the alert, manually creates a Slack channel, pastes the alert context, looks up who is on-call, finds the relevant runbook, and opens a Jira ticket. By the time the team is aligned and has context, five minutes have passed and the situation may have escalated. This pipeline compresses that five-minute setup to zero — by the time an engineer sees the notification, the channel, ticket, and runbook are already waiting.

---

## Architecture: Event-Driven Incident Automation

```
Alert Sources (Prometheus, CloudWatch)
         │
         ▼
    PagerDuty (on-call routing)
         │
         ▼ webhook
   API Gateway (HTTPS endpoint)
         │
         ▼
Lambda: Incident Router
    ├── Create Slack channel (#incident-<id>)
    ├── Post alert context + runbook link
    ├── Create Jira ticket (P1/P2/P3/P4)
    └── Lookup matching runbook
         │
         ▼
Lambda: Auto Remediator
    ├── restart pod (max 3 attempts)
    ├── scale up deployment
    ├── clean disk (logs older than 7 days)
    └── escalate to human if all fail
         │
   Resolved?
    ├── YES → Lambda: Postmortem Generator
    │             ├── Build timeline from PagerDuty API
    │             ├── Compute impact (users affected × duration)
    │             ├── Populate 5-Whys template
    │             ├── Store to S3
    │             └── Post to Slack + create Jira follow-up tickets
    └── NO  → Escalate (page backup on-call)
```

---

## Step-by-Step: Incident Automation Pipeline

### Step 1 — Infrastructure Deployment

```hcl
# terraform/main.tf (key resources)
resource "aws_api_gateway_rest_api" "incident_webhook" {
  name = "incident-automation-webhook"
}

resource "aws_lambda_function" "incident_router" {
  function_name = "incident-router"
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  
  environment {
    variables = {
      SLACK_TOKEN       = var.slack_token
      JIRA_URL          = var.jira_url
      JIRA_TOKEN        = var.jira_token
      RUNBOOK_BASE_URL  = var.runbook_base_url
      EKS_CLUSTER_NAME  = var.eks_cluster_name
    }
  }
}

resource "aws_s3_bucket" "postmortems" {
  bucket = "incident-postmortems-${var.account_id}"
  
  versioning {
    enabled = true  # postmortems are legal documents in some industries
  }
}
```

**Why API Gateway rather than an SNS subscription for the PagerDuty webhook?**  
PagerDuty webhooks send authenticated HTTP POST requests to HTTPS endpoints. SNS subscriptions require a different confirmation protocol. API Gateway provides a managed HTTPS endpoint with request validation and throttling. If PagerDuty retries a webhook (it will, on 5xx responses), API Gateway's throttling prevents Lambda from being invoked thousands of times.

### Step 2 — Incident Router Lambda

```python
# src/incident_router/handler.py
import json, boto3, os
from slack_sdk import WebClient
from jira import JIRA

SEVERITY_CONFIG = {
    "P1": {"channel_prefix": "p1-crit", "jira_priority": "Highest", "color": "#FF0000"},
    "P2": {"channel_prefix": "p2-high", "jira_priority": "High",    "color": "#FF6600"},
    "P3": {"channel_prefix": "p3-med",  "jira_priority": "Medium",  "color": "#FFCC00"},
    "P4": {"channel_prefix": "p4-low",  "jira_priority": "Low",     "color": "#0066FF"},
}

def lambda_handler(event, context):
    incident = json.loads(event['body'])['incident']
    severity = classify_severity(incident)
    incident_id = incident['id']
    
    config = SEVERITY_CONFIG[severity]
    
    # 1. Create Slack channel
    slack = WebClient(token=os.environ['SLACK_TOKEN'])
    channel = slack.conversations_create(
        name=f"{config['channel_prefix']}-{incident_id}"
    )
    
    # 2. Post incident summary + runbook link
    runbook_url = lookup_runbook(incident['title'])
    slack.chat_postMessage(
        channel=channel['channel']['id'],
        text=f"*{severity} Incident: {incident['title']}*\n"
             f"Runbook: {runbook_url}\n"
             f"Timeline: {incident['created_at']}"
    )
    
    # 3. Create Jira ticket
    jira = JIRA(os.environ['JIRA_URL'], token_auth=os.environ['JIRA_TOKEN'])
    ticket = jira.create_issue(
        project='OPS',
        summary=f"[{severity}] {incident['title']}",
        issuetype={'name': 'Incident'},
        priority={'name': config['jira_priority']}
    )
    
    # 4. Trigger auto-remediator
    boto3.client('lambda').invoke(
        FunctionName='auto-remediator',
        InvocationType='Event',  # async
        Payload=json.dumps({'incident': incident, 'jira_ticket': ticket.key})
    )
    
    return {'statusCode': 200}
```

**Why invoke the auto-remediator asynchronously (`InvocationType='Event'`)?**  
PagerDuty expects a webhook response within 10 seconds. If the incident router waits for auto-remediation to complete (which may take 30–60 seconds for a pod restart + health check), the webhook times out and PagerDuty retries — which would create a duplicate Slack channel and Jira ticket. Async invocation returns the 200 immediately; the remediator runs independently.

**Why Slack channel names are prefixed with severity?**  
Engineers in large organizations may be in 20+ Slack channels at any time. A channel named `incident-7A4B2C` is invisible in the sidebar. A channel named `p1-crit-7A4B2C` is immediately visible as urgent. Severity prefixes allow engineers to visually triage their channel list without opening each one.

### Step 3 — Auto Remediator Lambda

```python
# src/auto_remediator/handler.py
import boto3, time

REMEDIATION_MAP = {
    "HighErrorRate":        "restart_pod",
    "PodCrashLooping":      "restart_pod",
    "HighMemory":           "restart_pod",
    "DiskFull":             "clean_old_logs",
    "HighCPU":              "scale_up",
    "DatabaseConnectionMax": "scale_up",
}

MAX_REMEDIATION_ATTEMPTS = 3

def lambda_handler(event, context):
    incident = event['incident']
    alert_name = incident.get('alert_name', '')
    
    action = REMEDIATION_MAP.get(alert_name)
    if not action:
        escalate_to_human(incident, "No auto-remediation available")
        return
    
    for attempt in range(1, MAX_REMEDIATION_ATTEMPTS + 1):
        success = execute_remediation(action, incident)
        
        if success:
            notify_slack(incident, f"Auto-remediated: {action} (attempt {attempt})")
            generate_postmortem(incident)
            return
        
        time.sleep(30 * attempt)  # back off between attempts
    
    # All attempts failed → escalate
    escalate_to_human(incident, f"Auto-remediation failed after {MAX_REMEDIATION_ATTEMPTS} attempts")
```

**Why `MAX_REMEDIATION_ATTEMPTS = 3`?**  
Without a limit, a flapping service can cause the auto-remediator to restart a pod indefinitely — masking a real bug that requires human investigation. Three attempts is enough to handle transient issues (brief dependency unavailability, cold-start failures). After three failures, the problem is persistent and needs a human. Unlimited auto-remediation is more dangerous than no auto-remediation because it delays escalation.

**Why use exponential back-off between retry attempts (`sleep(30 * attempt)`)?**  
Restarting a pod immediately after it crashes doesn't give it time to become healthy. If the crash was caused by a dependency that needs 20 seconds to recover, the first restart will fail. Backing off gives dependencies time to recover before the next attempt, increasing the probability that each successive attempt succeeds.

### Step 4 — Postmortem Generator Lambda

```python
# src/postmortem_generator/handler.py
import boto3, json
from datetime import datetime

POSTMORTEM_TEMPLATE = """
# Postmortem: {title}

**Severity:** {severity}  
**Date:** {date}  
**Duration:** {duration_minutes} minutes  
**Services Affected:** {services}

## Impact
- Estimated users affected: {users_affected}
- Requests failed: {failed_requests}
- SLO budget consumed: {slo_budget_consumed}

## Timeline
{timeline}

## Root Cause (5 Whys)
1. Why did the service fail? [TO COMPLETE]
2. Why did that happen? [TO COMPLETE]
3. Why wasn't it caught earlier? [TO COMPLETE]
4. Why wasn't alerting more effective? [TO COMPLETE]
5. Why did this underlying condition exist? [TO COMPLETE]

## Action Items
| Item | Owner | Due Date |
|------|-------|----------|
| [FROM ROOT CAUSE ANALYSIS] | | |

## What Went Well
- Auto-remediation resolved the incident
- Runbook was accurate and up-to-date

## Lessons Learned
[TO COMPLETE]
"""

def lambda_handler(event, context):
    incident = event['incident']
    
    # Pull timeline from PagerDuty API
    timeline = build_timeline(incident['id'])
    
    # Compute SLO budget consumed from Prometheus
    slo_impact = query_slo_impact(incident)
    
    content = POSTMORTEM_TEMPLATE.format(
        title=incident['title'],
        severity=incident['severity'],
        date=datetime.now().strftime('%Y-%m-%d'),
        duration_minutes=slo_impact['duration_minutes'],
        services=', '.join(slo_impact['services']),
        users_affected=slo_impact['users_affected'],
        failed_requests=slo_impact['failed_requests'],
        slo_budget_consumed=slo_impact['budget_consumed'],
        timeline=timeline
    )
    
    # Store to S3
    s3 = boto3.client('s3')
    s3.put_object(
        Bucket=os.environ['POSTMORTEM_BUCKET'],
        Key=f"postmortems/{incident['id']}.md",
        Body=content
    )
```

**Why auto-generate postmortems rather than requiring manual authoring?**  
The biggest failure mode in postmortem culture is that postmortems don't get written. Under incident pressure, engineers resolve the issue and move on. Postmortem writing feels like extra work during recovery. By auto-generating the timeline, impact metrics, and template structure, the auto-generator creates a 60% complete document. The engineer only needs to fill in the 5 Whys analysis and action items — the hardest parts that require human judgment, not the mechanical parts that can be pulled from APIs.

**Why store postmortems in S3 with versioning enabled?**  
Postmortems are updated after the initial draft as root cause analysis deepens. Versioning in S3 provides a history of how the understanding of an incident evolved — which is itself valuable learning material. In regulated industries (healthcare, finance), postmortems are audit documents that must be retained for years; S3's durability (11 nines) and versioning satisfy that requirement.

### Step 5 — Severity Matrix

```markdown
# templates/severity-matrix.md

| Severity | Definition | Response SLA | Escalation |
|----------|-----------|-------------|------------|
| P1 | Revenue impact, >1% users affected | 15 minutes | CTO + VP Eng immediately |
| P2 | Degraded performance, partial outage | 1 hour | Engineering Manager |
| P3 | Minor issues, workaround available | 4 hours | Team lead |
| P4 | Cosmetic issues, no user impact | Next sprint | Backlog |
```

**Why written severity definitions rather than relying on judgment calls?**  
"Is this a P1 or P2?" is a debate that happens in real time during incidents, wasting minutes when the priority should be remediation. Written definitions with specific criteria (revenue impact, user percentage thresholds) convert a subjective judgment into an objective classification. The debate happens once when the matrix is written, not repeatedly during each incident.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **MTTR 45 → 8 minutes:** Automation eliminates the 5-minute setup phase (Slack, Jira, runbook lookup) and the human latency before the first remediation attempt
- **100% postmortem completion:** Auto-generation removes the friction that caused postmortem avoidance
- **Repeat incidents down 70%:** Because every incident now has a postmortem with tracked action items, root causes are addressed rather than ignored

### Security
- **Slack/Jira tokens in Lambda environment variables:** Not hardcoded in source; rotated independently of deployments
- **Auto-remediator blast radius limit:** `MAX_REMEDIATION_ATTEMPTS = 3` prevents runaway automation from making a bad situation worse
- **S3 versioning on postmortems:** Audit trail for incident documentation cannot be silently deleted or overwritten

### Reliability
- **Async Lambda invocation:** Incident router returns 200 to PagerDuty immediately; remediator runs independently — webhook never times out
- **Exponential back-off between retry attempts:** Gives recovering dependencies time to stabilize before next attempt
- **Auto-escalation on failure:** After 3 failed attempts, the system escalates to human rather than continuing to mask the problem

### Performance Efficiency
- **Lambda for event processing:** Only runs when an incident occurs — no idle infrastructure
- **API Gateway throttling:** Prevents PagerDuty retry storms from invoking Lambda thousands of times

### Cost Optimization
- **Serverless incident processing:** Pay-per-invocation; a team with 10 incidents/month pays less than $1 for the automation infrastructure
- **50% reduction in manual toil (20 → 10 hours/week):** Engineering time is the dominant cost; automation is always the correct investment at cloud rates

### Sustainability
- **Reduced incident-driven overtime:** Auto-remediation handles known issues at any hour — engineers are paged only when automation fails, reducing night wakeups

---

## Key Architectural Insight

The key design insight is that **incident management is a data problem**. Every piece of information needed to create a Slack channel, open a Jira ticket, find the right runbook, and draft a postmortem already exists in the systems involved (PagerDuty, Prometheus, Kubernetes, Git). The manual work is the act of gathering that information from separate tools and presenting it in the right format for the right audience. Automation does not replace human judgment about root cause — it eliminates the purely mechanical work, so engineers can focus entirely on the diagnostic work that actually requires human judgment.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
