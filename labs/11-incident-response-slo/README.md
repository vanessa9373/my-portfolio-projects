# Lab 11: Incident Response & SLO Monitoring

![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)

## Summary (The "Elevator Pitch")

Built a complete SLO monitoring and incident response framework — defined SLIs/SLOs, implemented error budget tracking, created burn-rate alerting, wrote operational runbooks, and conducted simulated incident response drills. This is the operational playbook that keeps production reliable.

## The Problem

The team monitored individual metrics (CPU, memory, pod count) but couldn't answer the question that matters most: **"Are we meeting our reliability promises to customers?"** When incidents happened, response was chaotic — no defined roles, no runbooks, no structured postmortems. The same issues repeated because no one tracked root causes systematically.

## The Solution

Implemented Google's SRE framework: **SLIs** measure what users care about (availability, latency), **SLOs** set targets (99.9% availability over 30 days), **error budgets** quantify allowed unreliability, and **burn-rate alerts** catch problems before the budget runs out. Built operational runbooks and conducted tabletop incident drills so the team practices before real incidents hit.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Grafana SLO Dashboard                │
│  ┌───────────┐  ┌──────────┐  ┌───────────────────┐ │
│  │ Current   │  │ Error    │  │ Budget Burn Rate  │ │
│  │ SLO: 99.92│  │ Budget:  │  │ ████████░░  78%   │ │
│  │           │  │ 43 min   │  │ remaining         │ │
│  └───────────┘  └──────────┘  └───────────────────┘ │
└──────────────────────────────────────────────────────┘
        ▲                              │
        │                              ▼
┌───────────────┐              ┌──────────────┐
│  Prometheus   │              │ Alertmanager │
│  Recording    │              │              │
│  Rules        │              │ Burn > 14x → P1 (page)
│  (SLI calc)   │              │ Burn > 6x  → P2 (ticket)
└───────────────┘              │ Burn > 1x  → P3 (log)
                               └──────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| Prometheus | SLI calculation with recording rules | PromQL enables complex SLO math |
| Grafana | SLO dashboards and error budget visualization | Real-time budget tracking |
| Alertmanager | Burn-rate alert routing | Severity-based escalation |
| Python | Incident simulation scripts | Inject failures for drills |
| Markdown | Runbooks and postmortem templates | Version-controlled documentation |

## Implementation Steps

### Step 1: Define SLIs and SLOs
**What this does:** Documents what to measure (SLIs) and what targets to set (SLOs) for each service tier.
```
Tier 1 Services (checkout, payment):  99.99% availability, p99 latency < 200ms
Tier 2 Services (catalog, cart):      99.9%  availability, p99 latency < 500ms
Tier 3 Services (recommendations):    99.5%  availability, p99 latency < 1000ms
```

### Step 2: Create Prometheus Recording Rules
**What this does:** Pre-calculates SLI values every 30 seconds so dashboards and alerts query efficiently.
```bash
kubectl apply -f prometheus/recording-rules.yaml
```

### Step 3: Configure Burn-Rate Alerts
**What this does:** Alerts based on how fast the error budget is being consumed, not raw error counts.
```bash
kubectl apply -f prometheus/burn-rate-alerts.yaml
```

### Step 4: Build Grafana Dashboards
**What this does:** Creates SLO dashboards showing current compliance, remaining error budget, and burn rate trends.
```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
# Import dashboards from grafana/ directory
```

### Step 5: Write Operational Runbooks
**What this does:** Creates step-by-step guides for common incidents (high error rate, latency spike, disk full, OOM kills).

### Step 6: Conduct Incident Drill
**What this does:** Simulates a production incident — injects failure, practices the response process (detect → triage → mitigate → resolve → postmortem).
```bash
python scripts/simulate-incident.py --type latency-spike --service checkout
```

## Project Structure

```
11-incident-response-slo/
├── README.md
├── prometheus/
│   ├── recording-rules.yaml     # SLI recording rules (availability, latency)
│   ├── burn-rate-alerts.yaml    # Multi-window burn-rate alerting
│   └── alertmanager-config.yaml # Routing: P1→PagerDuty, P2→Slack, P3→log
├── grafana/
│   └── slo-dashboard.json       # SLO compliance and error budget dashboard
├── runbooks/
│   ├── high-error-rate.md       # Step-by-step: diagnose → mitigate → resolve
│   ├── latency-spike.md         # Latency troubleshooting guide
│   └── disk-full.md             # Disk cleanup procedures
├── scripts/
│   └── simulate-incident.py     # Inject failures for drill practice
└── docs/
    ├── slo-definitions.md       # Tiered SLO framework
    ├── error-budget-policy.md   # What happens when budget is exhausted
    └── postmortem-template.md   # Blameless postmortem format
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `prometheus/recording-rules.yaml` | Pre-calculates SLI ratios every 30s for efficient querying | PromQL recording rules, SLI math |
| `prometheus/burn-rate-alerts.yaml` | Multi-window alerts: 1h/6h for fast burns, 3d for slow burns | Burn-rate alerting methodology |
| `docs/slo-definitions.md` | 3-tier SLO framework with error budget policies and escalation | SRE framework design |
| `runbooks/high-error-rate.md` | Step-by-step: check dashboards → identify service → check logs → rollback if needed | Operational procedures |
| `scripts/simulate-incident.py` | Injects CPU stress, network latency, or pod failures for drills | Chaos engineering, incident practice |

## Results & Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Reliability Measurement | None ("feels okay") | Quantified SLOs | **Data-driven reliability** |
| Alert Quality | Noisy thresholds | Burn-rate alerts | **Meaningful alerts only** |
| Incident Response | Chaotic ad-hoc | Structured + rehearsed | **Consistent process** |
| Repeat Incidents | Common (no postmortems) | Rare (action items tracked) | **Fewer recurrences** |

## How I'd Explain This in an Interview

> "The team monitored CPU and memory but couldn't answer 'are we meeting our reliability promises?' I implemented Google's SRE framework — defined SLIs (availability, latency), set tiered SLOs (99.99% for payment, 99.5% for recommendations), and built burn-rate alerting that only fires when the error budget is being consumed too fast. I also built operational runbooks and ran tabletop incident drills so the team practices the response process before real incidents. The key shift was from 'how much CPU are we using?' to 'are we meeting our SLO?' — which is what actually matters to customers."

## Key Concepts Demonstrated

- **SLI/SLO/Error Budgets** — Google SRE reliability framework
- **Multi-Window Burn-Rate Alerting** — Intelligent alerting that reduces noise
- **Operational Runbooks** — Step-by-step guides for common incidents
- **Incident Response Drills** — Tabletop exercises for team practice
- **Blameless Postmortems** — Learning from incidents without blame
- **Error Budget Policy** — Defines consequences when budget is exhausted

## Lessons Learned

1. **Burn-rate > threshold alerts** — "error rate > 1%" is noisy; "budget burning at 14x" is actionable
2. **Tiered SLOs match business value** — payment services need 99.99%; recommendations can be 99.5%
3. **Drill before real incidents** — practiced teams respond 3x faster
4. **Error budget policy needs teeth** — if budget is exhausted, feature work stops and reliability work begins
5. **Postmortems need action items with owners** — without follow-through, the same issues recur

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
