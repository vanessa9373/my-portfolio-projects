# Lab 11: Incident Response & SLO Monitoring — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** Google SRE Book (Site Reliability Engineering, Chapters 4–6) + AWS Well-Architected Framework  
> **Scope:** SLO framework, error budget tracking, burn-rate alerting, operational runbooks, incident drills

---

## What This Platform Solves

Monitoring CPU utilization and pod restarts tells you about resource consumption. It cannot tell you whether you are meeting your reliability promises to customers. A service that consumes 90% CPU but answers every request correctly is healthy. A service consuming 40% CPU but timing out on 5% of requests is in breach. This lab shifts the monitoring question from "how are we using resources?" to "are we meeting our SLO?"

---

## Architecture: The SRE Alerting Stack

```
  Kubernetes workloads
        │
        ▼
  Prometheus (recording rules: SLI ratios every 30s)
        │
        ├── Grafana (SLO compliance + error budget dashboard)
        │
        └── Alertmanager (burn-rate routing)
              │
              ├── P1 (burn > 14×) → PagerDuty (immediate page)
              ├── P2 (burn > 6×)  → Slack (ticket created)
              └── P3 (burn > 1×)  → Log (awareness only)
```

---

## Step-by-Step: SLO Monitoring Platform

### Step 1 — Tiered SLO Definitions

```
Tier 1 (Revenue-critical: checkout, payment):
  Availability SLO:  99.99% over 30 days = 4.32 minutes allowed downtime
  Latency SLO:       p99 < 200ms, 99% of the time over 30 days

Tier 2 (Customer-facing: catalog, cart, frontend):
  Availability SLO:  99.9% over 30 days = 43.2 minutes allowed downtime
  Latency SLO:       p99 < 500ms, 99% of the time over 30 days

Tier 3 (Non-critical: recommendations, ads):
  Availability SLO:  99.5% over 30 days = 3.6 hours allowed downtime
  Latency SLO:       p99 < 1000ms, 95% of the time over 30 days
```

**Why tiered SLOs?**  
A uniform 99.99% SLO for every service forces the recommendations engine to require the same engineering investment as the payment service. Payment failures cost revenue immediately; recommendation failures reduce engagement slowly. Tiers ensure engineering effort is proportional to business impact. The tier also determines on-call severity — a Tier 3 outage is a next-business-day ticket; a Tier 1 outage is a 2am page.

**Why 30-day rolling window rather than calendar month?**  
Calendar months vary in length and reset at midnight on the last day of the month. A team that deploys a bad change on the 29th can argue "the month was almost over anyway." A 30-day rolling window has no reset point — compliance is always measured against the last 30 days of behavior, making the budget gaming impossible.

### Step 2 — Prometheus Recording Rules for SLIs

```yaml
# prometheus/recording-rules.yaml
groups:
  - name: slo-recording-rules
    interval: 30s
    rules:
      # Availability SLI: fraction of requests that succeeded
      - record: slo:http_request_success_rate:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m])) by (job)
          /
          sum(rate(http_requests_total[5m])) by (job)

      # 30-day window for compliance reporting
      - record: slo:http_request_success_rate:ratio_rate30d
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[30d])) by (job)
          /
          sum(rate(http_requests_total[30d])) by (job)

      # Latency SLI: fraction of requests meeting the target
      - record: slo:http_request_latency_sli:ratio_rate5m
        expr: |
          sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m])) by (job)
          /
          sum(rate(http_request_duration_seconds_count[5m])) by (job)
```

**Why recording rules instead of computing in dashboards?**  
The `ratio_rate30d` expression requires Prometheus to scan 30 days of time-series data for every evaluation. A Grafana dashboard with a 10-second refresh interval running this expression would trigger 6 expensive scans per minute. Recording rules evaluate the expression once every 30 seconds and store the result as a new, lightweight time series. Dashboards and alerts then read the pre-computed result — query cost is constant regardless of how many users have the dashboard open.

**Why both 5-minute and 30-day windows?**  
The 5-minute window detects current problems — is something wrong right now? The 30-day window measures SLO compliance — have we met our promise over the last month? Burn-rate alerting uses both: fast burn uses the 5-minute window to confirm the problem is ongoing, while the 30-day window determines the budget remaining to be consumed.

### Step 3 — Multi-Window Burn-Rate Alerting

```yaml
# prometheus/burn-rate-alerts.yaml
groups:
  - name: slo-burn-rate-alerts
    rules:
      # Fast burn: both 1h and 5m windows must confirm
      - alert: HighBurnRate
        expr: |
          (
            slo:http_request_success_rate:ratio_rate1h{job="checkout"} < (1 - 14.4 * 0.001)
          AND
            slo:http_request_success_rate:ratio_rate5m{job="checkout"} < (1 - 14.4 * 0.001)
          )
        for: 1m
        labels:
          severity: critical
          tier: "1"
        annotations:
          summary: "Checkout: budget burning at 14.4× — exhausted in 2 days"

      # Slow burn: both 6h and 30m windows must confirm
      - alert: LowBurnRate
        expr: |
          (
            slo:http_request_success_rate:ratio_rate6h{job="checkout"} < (1 - 6 * 0.001)
          AND
            slo:http_request_success_rate:ratio_rate30m{job="checkout"} < (1 - 6 * 0.001)
          )
        for: 15m
        labels:
          severity: warning
          tier: "1"
```

**Why AND-ing two windows instead of one?**  
A single-window alert (1h only) can fire because error rate was elevated for 30 minutes but has already recovered. The AND condition requires the problem to be both *sustained* (1h window still elevated) and *current* (5m window still elevated). An incident that resolved 20 minutes ago passes the 5m check. A brief spike that resolved passes the 1h check. Only an ongoing problem fails both.

**The burn rate algebra:**
```
SLO target: 99.9% (error budget = 0.1% over 30 days)
Burn rate 1×  = consuming budget at exactly the rate that exhausts it in 30 days
Burn rate 14.4× = 30 / 14.4 = 2.08 days to exhaustion
Burn rate 6×   = 30 / 6    = 5 days to exhaustion
```

This table drives the four alert tiers (per Google's SRE Book, Chapter 5):

| Burn Rate | Long Window | Short Window | Budget Consumed | Min to Detect |
|-----------|-------------|-------------|----------------|---------------|
| 14.4×     | 1 hour      | 5 minutes   | 2%             | ~2 min        |
| 6×        | 6 hours     | 30 minutes  | 5%             | ~15 min       |
| 3×        | 1 day       | 2 hours     | 10%            | ~1 hr         |
| 1×        | 3 days      | 6 hours     | 10%            | ~6 hr         |

### Step 4 — Alertmanager Routing

```yaml
# prometheus/alertmanager-config.yaml
route:
  receiver: 'default'
  routes:
    - matchers:
        - severity = critical
        - tier = "1"
      receiver: 'pagerduty-tier1'
    
    - matchers:
        - severity = warning
      receiver: 'slack-oncall'
    
    - matchers:
        - severity = info
      receiver: 'slack-log'

receivers:
  - name: 'pagerduty-tier1'
    pagerduty_configs:
      - routing_key: '$PAGERDUTY_KEY'
        severity: critical

  - name: 'slack-oncall'
    slack_configs:
      - api_url: '$SLACK_WEBHOOK'
        channel: '#incidents'
```

**Why route by tier as well as severity?**  
A Tier 3 service at critical burn rate (14.4×) should not page the on-call engineer at 2am — Tier 3 services have a 3.6-hour error budget and can wait until business hours. Routing on both severity and tier ensures PagerDuty calls only fire for Tier 1/2 services. Tier 3 incidents go to Slack where they're visible but don't wake anyone up.

### Step 5 — Operational Runbooks

```markdown
# runbooks/high-error-rate.md

## High Error Rate Runbook

### When to use this
Alert: HighBurnRate, severity=critical, any Tier 1 service

### Step 1: Assess impact (2 minutes)
- Open Grafana SLO dashboard: error rate trend, which service, which endpoint?
- Check error budget remaining: kubectl port-forward svc/grafana 3000:80

### Step 2: Identify scope (3 minutes)
- Single pod or all pods? kubectl get pods -n sre-demo
- Recent deployment? kubectl rollout history deployment/<service>
- Dependency failure? Check dependent services' error rates

### Step 3: Mitigate (5 minutes)
- Bad deploy: kubectl rollout undo deployment/<service>
- Dependency overload: check SQS queue depth / DB connection pool
- Traffic spike: verify HPA has scaled / manually scale if stuck

### Step 4: Resolve and document
- Confirm SLI returning to target in Grafana
- Post incident summary in #incidents Slack channel
- Open postmortem ticket if budget impact > 10%
```

**Why version-controlled runbooks in Markdown rather than a wiki?**  
Wikis are often updated in response to incidents and then forgotten. A runbook in the Git repository is reviewed with the same process as code changes — PRs, comments, approval. When a runbook step fails during an incident, the engineer files a ticket and updates the runbook in the next sprint. Git blame shows when each step was last validated.

### Step 6 — Incident Simulation Drills

```python
# scripts/simulate-incident.py
import subprocess
import time
import argparse

def simulate_latency_spike(service, duration_seconds):
    """Inject latency into a pod using tc (traffic control)"""
    pods = get_pods(service)
    for pod in pods[:1]:  # single pod to limit blast radius
        subprocess.run([
            "kubectl", "exec", pod, "--",
            "tc", "qdisc", "add", "dev", "eth0", "root",
            "netem", "delay", "500ms"
        ])
    
    print(f"Injected 500ms latency into {pod}")
    time.sleep(duration_seconds)
    
    # Cleanup
    subprocess.run([
        "kubectl", "exec", pod, "--",
        "tc", "qdisc", "del", "dev", "eth0", "root"
    ])
    print("Latency removed — check if alert fired and was resolved")
```

**Why run incident drills before real incidents happen?**  
A team that has never run the checkout-service rollback command will take 15 minutes to find the right command, check the documentation, and verify the result when it matters at 2am. A team that has practiced the same rollback 10 times in drills takes 2 minutes. Drills also reveal runbook gaps — steps that say "check the logs" without specifying where, or rollback commands that have changed since the runbook was written.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Burn-rate alerting:** Replaces 20+ threshold alerts with 4 intelligent ones — 60% alert noise reduction
- **Runbooks in Git:** Version-controlled, reviewed, and linked from alerts — engineers always have the current procedure
- **Error budget policy:** When budget is exhausted, feature work stops — reliability work becomes the team's top priority, enforced by the SLO framework not by management judgment

### Security
- **Read-only Prometheus queries:** SLO calculator only reads metrics — no write access, no ability to mutate data
- **Alertmanager credentials in Kubernetes Secrets:** PagerDuty routing key and Slack webhook not in plaintext config files

### Reliability
- **Multi-window alerts:** Eliminates false alarms from transient spikes — alert only fires for persistent problems
- **Tiered SLOs:** Payment service at 99.99%; recommendations at 99.5% — over-engineering non-critical services wastes reliability budget on low-impact services
- **Incident drills:** Team has rehearsed response procedures — MTTR is lower because actions are practiced

### Performance Efficiency
- **Recording rules pre-compute expensive queries:** 30-day rolling windows evaluated once every 30s, not on every dashboard load or alert evaluation
- **Alert firing conditions:** `for: 1m` on critical alerts prevents alert churn from brief evaluation anomalies

### Cost Optimization
- **Alert reduction:** 60% fewer alerts means 60% less on-call time spent investigating false positives — engineering time is the dominant cost
- **Tiered SLOs prevent over-engineering:** Tier 3 services use 99.5% targets — no Tier-1-grade reliability investment required

### Sustainability
- **Error budget governance:** Budget exhaustion triggers reliability work rather than indefinite accumulation of reliability debt — prevents the expensive emergency remediation that results from ignored degradation

---

## Key Architectural Insight

The deepest change in SRE monitoring is not technical — it is economic. Before error budgets, deploying a new feature and maintaining reliability are in tension: the feature team wants to ship, the reliability team wants stability. The dispute is political. With error budgets, the dispute becomes a calculation: "We have 18 minutes of budget remaining. This deploy has a 30% chance of a 10-minute incident. Expected cost = 3 minutes. 18 > 3. We can ship." The error budget converts a political argument into an arithmetic problem — and arithmetic has a clear answer.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
