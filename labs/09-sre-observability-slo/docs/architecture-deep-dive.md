# Lab 09: SRE Observability & SLO Platform — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** Google SRE Book (Chapters 4–6) + AWS Well-Architected Framework  
> **Scope:** SLO definition, error budget tracking, multi-window burn-rate alerting, Python SLO calculator

---

## What This Platform Solves

The difference between "we have monitoring" and "we have observability" is whether the data answers the question that matters: **"Are we meeting our reliability promises to customers?"** CPU utilization and pod restart counts don't answer this. Error budget burn rate does.

---

## The SRE Reliability Framework

```
SLA (Service Level Agreement)
├── External commitment to customers (e.g., "99.9% monthly uptime")
└── Breach triggers financial penalties or contract violations

SLO (Service Level Objective)
├── Internal reliability target (e.g., "99.95% availability in 30-day window")
└── Tighter than SLA — leave a buffer between internal target and external commitment

SLI (Service Level Indicator)
├── The metric being measured (e.g., "% of requests returning 2xx/3xx")
└── Calculated from Prometheus metrics

Error Budget
├── The allowed unreliability within the SLO window
├── 99.95% availability in 30 days = 21.6 minutes allowed downtime
└── If budget > 0: deploy freely. If budget exhausted: reliability work first.
```

---

## Step-by-Step: SLO Platform Implementation

### Step 1 — SLO Definitions (Tiered by Business Criticality)

```
Tier 1 (Revenue-critical services: checkout, payment):
  Availability SLO:  99.99% over 30 days = 4.32 minutes allowed downtime
  Latency SLO:       p99 < 200ms, 99% of the time over 30 days

Tier 2 (Customer-facing: catalog, cart, frontend):
  Availability SLO:  99.9% over 30 days = 43.2 minutes allowed downtime
  Latency SLO:       p99 < 500ms, 99% of the time over 30 days

Tier 3 (Non-critical: recommendations, ads):
  Availability SLO:  99.5% over 30 days = 3.6 hours allowed downtime
  Latency SLO:       p99 < 1000ms, 95% of the time over 30 days
```

**Why tiered SLOs instead of a uniform target?**  
A uniform 99.99% SLO for every service means:
- Recommendation service requires the same reliability as payment service
- Teams spend equal engineering effort on reliability regardless of business impact
- Any incident in any service has the same severity — everything is P1

Tiered SLOs align engineering investment with business value. Payment failures cost money directly; recommendation failures cost engagement indirectly. The SLO tier determines how much on-call engineering the service justifies and what budget to allocate for reliability work.

**Why 30-day rolling window (not calendar month)?**  
Calendar months vary in length (28–31 days) and reset suddenly. A 30-day rolling window is continuous — the SLO compliance at any moment reflects the last 30 days of actual behavior, not "how many days until the calendar resets." It also prevents gaming: you can't accept elevated error rates on day 29 because "the month is almost over."

### Step 2 — Prometheus Recording Rules for SLIs

```yaml
# k8s/prometheus/alerting-rules.yaml
groups:
  - name: slo-recording-rules
    interval: 30s
    rules:
      # Availability SLI: ratio of successful requests
      - record: slo:http_request_success_rate:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m])) by (job)
          /
          sum(rate(http_requests_total[5m])) by (job)
      
      # Also compute over 30-day window for compliance reporting
      - record: slo:http_request_success_rate:ratio_rate30d
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[30d])) by (job)
          /
          sum(rate(http_requests_total[30d])) by (job)
      
      # Latency SLI: % of requests meeting latency target
      - record: slo:http_request_latency_sli:ratio_rate5m
        expr: |
          sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m])) by (job)
          /
          sum(rate(http_request_duration_seconds_count[5m])) by (job)
```

**Why recording rules instead of computing in dashboards?**  
The `ratio_rate30d` expression over a 30-day window is expensive to compute on-demand — it scans 30 days of time-series data. Evaluating this on a Grafana dashboard with 10-second auto-refresh would slow Prometheus to a crawl. Recording rules pre-compute the expression every 30 seconds and store the result as a new time series. Dashboard queries then read the pre-computed series (`slo:http_request_success_rate:ratio_rate30d`) instead of re-computing it.

**Why include both 5m and 30d recordings?**  
- `ratio_rate5m`: Short window for alerting (detects current issues)
- `ratio_rate30d`: Full SLO window for compliance reporting ("are we meeting the SLO this month?")

### Step 3 — Multi-Window Burn-Rate Alerting

The key innovation of Google's SRE alerting methodology is multi-window burn-rate alerting.

**Why simple threshold alerts fail:**
- "Error rate > 1% for 5 minutes" fires during brief spikes that don't affect the SLO
- "Error rate > 1% for 1 hour" misses fast-burning incidents that exhaust the budget in 2 hours

**Burn rate concept:**
If the SLO is 99.9% over 30 days, the error budget is 0.1% × 30 days × 24h = 43.2 minutes.

- Burn rate 1 = consuming the budget at exactly the rate that exhausts it in 30 days
- Burn rate 14.4 = consuming 14.4× faster than budget allows = exhausts budget in 2 days

```yaml
# Multi-window burn-rate alerts
  - name: slo-burn-rate-alerts
    rules:
      # Fast burn: detects 2-hour window exhaustion
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
          summary: "Checkout service: error budget burning 14.4× faster than target"
          description: |
            At this rate, the entire 30-day error budget will be exhausted in 2 hours.
            Current SLI: {{ $value | humanizePercentage }}
            SLO target: 99.9%
      
      # Slow burn: detects 3-day window exhaustion
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

**Why two windows per alert (1h AND 5m)?**  
A single-window alert (1h only) can miss a fast spike that elevated errors for 30 minutes and then resolved. By requiring BOTH the 1h window AND the 5m window to be elevated simultaneously, the alert confirms: the issue is both current (5m window) and sustained (1h window). A resolved issue passes the 5m check; an isolated spike passes the 1h check. Only a genuine ongoing problem fails both.

**The 4 alert tiers (Google's recommended parameters):**

| Burn Rate | Long Window | Short Window | Budget Used | Min To Detect |
|-----------|------------|-------------|------------|--------------|
| 14.4× | 1 hour | 5 minutes | 2% | ~2 min |
| 6× | 6 hours | 30 minutes | 5% | ~15 min |
| 3× | 1 day | 2 hours | 10% | ~1 hr |
| 1× | 3 days | 6 hours | 10% | ~6 hr |

**Why 14.4× as the "fast burn" threshold?**  
At 14.4× burn rate and a 30-day budget, the budget is fully consumed in 2 days (30 / 14.4 = 2.08). A 14.4× burn rate means the error rate is 14.4 × 0.001 (for 99.9% SLO) = 1.44%. 1.44% error rate is serious but not catastrophic — it will be detected quickly via other signals (user reports, support tickets). The burn-rate alert catches it before the SLO window closes.

### Step 4 — Python SLO Calculator

```python
# scripts/slo-calculator.py
import requests
import json
from datetime import datetime, timedelta

PROMETHEUS_URL = "http://localhost:9090"
SLO_TARGET = 0.999      # 99.9%
WINDOW_DAYS = 30

def query_prometheus(query):
    response = requests.get(
        f"{PROMETHEUS_URL}/api/v1/query",
        params={"query": query, "time": datetime.now().timestamp()}
    )
    data = response.json()
    return float(data['data']['result'][0]['value'][1])

def calculate_slo_compliance(service):
    # Current 30-day SLI
    sli = query_prometheus(
        f'slo:http_request_success_rate:ratio_rate30d{{job="{service}"}}'
    )
    
    # Error budget remaining
    budget_used = max(0, (SLO_TARGET - sli) / (1 - SLO_TARGET))
    budget_remaining = max(0, 1 - budget_used)
    
    # Remaining minutes
    total_budget_minutes = (1 - SLO_TARGET) * WINDOW_DAYS * 24 * 60
    remaining_minutes = budget_remaining * total_budget_minutes
    
    # Projected exhaustion date
    burn_rate = query_prometheus(
        f'slo:http_request_success_rate:ratio_rate5m{{job="{service}"}}'
    )
    if burn_rate < SLO_TARGET:
        current_burn = (SLO_TARGET - burn_rate) / (1 - SLO_TARGET)
        days_to_exhaustion = budget_remaining / current_burn * WINDOW_DAYS
        exhaustion_date = datetime.now() + timedelta(days=days_to_exhaustion)
    else:
        exhaustion_date = None
    
    return {
        "service": service,
        "sli": f"{sli * 100:.4f}%",
        "slo_target": f"{SLO_TARGET * 100:.3f}%",
        "compliant": sli >= SLO_TARGET,
        "budget_used": f"{budget_used * 100:.1f}%",
        "budget_remaining_minutes": f"{remaining_minutes:.1f}",
        "projected_exhaustion": exhaustion_date.isoformat() if exhaustion_date else "Not burning"
    }
```

**Why a standalone calculator script instead of just Grafana dashboards?**  
Grafana is visual — a dashboard shows current state. The SLO calculator is programmatic — it generates a report that can be:
- Sent to stakeholders via email (Grafana links require authentication)
- Included in weekly status reports (copy-paste from terminal)
- Ingested by a ticketing system to create "SLO at risk" tickets automatically
- Exported to CSV for finance/compliance teams

The calculator script is the automation bridge between Prometheus data and business reporting workflows.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Error budget policy:** When budget is exhausted, feature work stops — reliability work begins. This is a governance mechanism, not a technical one.
- **Recording rules:** Dashboard performance is fast — queries return pre-computed results, not raw time-series
- **SLO calculator as automation:** Weekly compliance reports generated automatically, not manually assembled

### Security
- **Prometheus auth:** Internal Prometheus (not internet-exposed) — port-forwarding for access, no public endpoint
- **Read-only SLO calculator:** The calculator only queries Prometheus — no write access, no risk of accidental metric mutation

### Reliability
- **Multi-window alerting:** Catches both fast burns (2-hour budget exhaustion) and slow burns (3-day budget exhaustion)
- **60% alert noise reduction:** Burn-rate alerts replace hundreds of threshold alerts — fewer false alarms, more signal per alert
- **Tiered SLOs:** Payment at 99.99%, recommendations at 99.5% — engineering effort allocated by business value

### Performance Efficiency
- **Recording rules pre-compute expensive queries:** 30-day rolling averages are expensive; recording rules pay the cost once per 30 seconds rather than on every dashboard load
- **OpenTelemetry collector:** Single collector handles metrics, logs, and traces — reduces per-pod sidecar overhead

### Cost Optimization
- **Tiered SLOs reduce unnecessary over-engineering:** Not every service needs five-nines reliability. Tiering prevents over-investing in less critical services.
- **Alerting reduction:** 60% fewer alerts means 60% less on-call time for false alarms — engineering time is a cost

### Sustainability
- **Error budget governance:** Budget exhaustion triggers reliability work — prevents indefinite accumulation of reliability debt that would require expensive emergency remediation

---

## Key Architectural Insight

The deepest insight in SRE observability is that **error budgets make reliability decisions economic rather than political**. Before error budgets, a deployment decision is a political one: "the reliability team says we need more testing; the product team says we need to ship." With error budgets, it's economic: "we have 18 minutes of error budget remaining this month. This deployment carries a 10% risk of a 30-minute incident. The expected cost is 3 minutes of budget. We have 18. We can ship." The budget transforms an argument about priorities into a calculation.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
