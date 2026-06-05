# Phase 8: Observability & Monitoring

**Difficulty:** Advanced | **Time:** 6-8 hours | **Prerequisites:** Phase 7

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Step-by-Step Implementation](#3-step-by-step-implementation)
4. [Configuration Walkthrough](#4-configuration-walkthrough)
5. [Verification Checklist](#5-verification-checklist)
6. [Troubleshooting](#6-troubleshooting)
7. [Key Decisions & Trade-offs](#7-key-decisions--trade-offs)
8. [Production Considerations](#8-production-considerations)
9. [Next Phase](#9-next-phase)

---

## 1. Overview

Observability is the ability to understand a system's internal state from its external outputs. This phase implements the three pillars of observability plus SLO-based alerting:

### The Three Pillars

```
┌──────────────────────────────────────────────────────────────┐
│                     Observability Stack                       │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  Prometheus  │  │    Loki      │  │   Jaeger     │       │
│  │  (Metrics)   │  │   (Logs)     │  │  (Traces)    │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │                │
│         └────────────┬────┘─────────────────┘                │
│                      ▼                                       │
│              ┌──────────────┐                                │
│              │   Grafana    │                                │
│              │ (Dashboards) │                                │
│              └──────────────┘                                │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │           Alertmanager → PagerDuty               │       │
│  │     SLO burn rate alerts, error budget alerts    │       │
│  └──────────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────────┘
```

| Pillar | Tool | Purpose |
|--------|------|---------|
| **Metrics** | Prometheus | Time-series data: request rates, latencies, error counts |
| **Logs** | Loki | Structured log aggregation from all pods |
| **Traces** | Jaeger + OpenTelemetry | Distributed request tracing across services |
| **Dashboards** | Grafana | Unified visualization for all three pillars |
| **Alerting** | Alertmanager | SLO-based alerts routed to PagerDuty/Slack |

### SLO Strategy

The platform uses **SLO-based alerting** instead of threshold-based alerts:
- **SLO target:** 99.95% availability (26.3 minutes of downtime/month allowed)
- **Error budget:** 0.05% of requests can fail before alerting
- **Burn rate alerts:** Alert when error budget is being consumed too quickly

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Helm | 3.13+ | Installed in Phase 6 |
| kubectl | 1.28+ | Installed in Phase 4 |

### Install the Observability Stack

```bash
# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin

# Install Loki
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true
```

---

## 3. Step-by-Step Implementation

### Step 1: Create SLO Recording Rules

The SLO rules calculate availability and latency ratios that power the alerting system. Apply `prometheus/slo-rules.yml`:

```bash
# Create a ConfigMap with the recording rules
kubectl create configmap slo-rules \
  --from-file=slo-rules.yml=prometheus/slo-rules.yml \
  -n monitoring

# Or apply as a PrometheusRule CRD (if using kube-prometheus-stack)
kubectl apply -f prometheus/slo-rules.yml -n monitoring
```

### Step 2: Configure Alertmanager

```yaml
# alertmanager.yml (applied via Helm values or ConfigMap)
route:
  receiver: 'pagerduty-critical'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
    - match:
        severity: warning
      receiver: 'slack-warnings'

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '<PAGERDUTY_INTEGRATION_KEY>'
  - name: 'slack-warnings'
    slack_configs:
      - api_url: '<SLACK_WEBHOOK_URL>'
        channel: '#platform-alerts'
```

### Step 3: Import Grafana Dashboards

```bash
# Import the SLO dashboard
kubectl create configmap grafana-slo-dashboard \
  --from-file=slo-overview.json=grafana/dashboards/slo-overview.json \
  -n monitoring \
  -o yaml --dry-run=client | \
  kubectl label --local -f - grafana_dashboard=1 -o yaml | \
  kubectl apply -f -
```

Access Grafana:

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Open http://localhost:3000
# Login: admin / admin
```

### Step 4: Configure Loki for Log Aggregation

Apply `loki/loki-config.yaml`:

```bash
# Loki is installed via Helm with Promtail
# Promtail automatically discovers and ships logs from all pods
# Verify Promtail is running on all nodes
kubectl get pods -n monitoring -l app=promtail
```

### Step 5: Instrument Services with OpenTelemetry

Add the OpenTelemetry SDK to each service for distributed tracing:

```bash
# Node.js services
npm install @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node

# Python services
pip install opentelemetry-api opentelemetry-sdk opentelemetry-instrumentation-fastapi
```

### Step 6: Verify the Stack

```bash
# Check Prometheus targets
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090
# Open http://localhost:9090/targets — all targets should be UP

# Check Loki logs
# In Grafana → Explore → select Loki data source → query: {namespace="production"}

# Check Jaeger traces
kubectl port-forward svc/jaeger-query -n monitoring 16686:16686
# Open http://localhost:16686
```

---

## 4. Configuration Walkthrough

### `prometheus/slo-rules.yml` — Section by Section

#### Recording Rules Group

```yaml
groups:
  - name: slo-rules
    interval: 30s          # Evaluate these rules every 30 seconds
    rules:
```

Recording rules pre-compute expensive queries so dashboards and alerts are fast.

#### Availability SLI (5-minute window)

```yaml
      - record: slo:api_availability:ratio_rate5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total[5m]))
```

- **Numerator:** Rate of non-5xx requests over 5 minutes
- **Denominator:** Rate of all requests over 5 minutes
- **Result:** A value between 0 and 1 (e.g., 0.9998 = 99.98% availability)
- `status!~"5.."` excludes all 5xx status codes (500, 502, 503, etc.)

#### Availability SLI (1-hour window)

```yaml
      - record: slo:api_availability:ratio_rate1h
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[1h]))
          /
          sum(rate(http_requests_total[1h]))
```

Longer window smooths out brief spikes — used for error budget calculation.

#### Latency SLI

```yaml
      - record: slo:api_latency:ratio_rate5m
        expr: |
          sum(rate(http_request_duration_seconds_bucket{le="0.2"}[5m]))
          /
          sum(rate(http_request_duration_seconds_count[5m]))
```

- **Numerator:** Rate of requests completed under 200ms (`le="0.2"`)
- **Denominator:** Rate of all requests
- **Result:** Percentage of requests meeting the latency target

#### Error Budget Remaining

```yaml
      - record: slo:error_budget:remaining
        expr: |
          1 - (
            (1 - slo:api_availability:ratio_rate1h)
            /
            (1 - 0.9995)
          )
```

- **SLO target:** 99.95% (0.9995)
- **Error budget:** 0.05% of requests can fail
- If availability drops to 99.90%, the formula gives: `1 - (0.001 / 0.0005) = 1 - 2 = -1` (budget exhausted)
- A value > 0 means budget remains; < 0 means SLO is breached

#### Alerts Group

```yaml
  - name: slo-alerts
    rules:
      - alert: SLOBurnRateHigh
        expr: slo:api_availability:ratio_rate5m < 0.999
        for: 5m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "API SLO burn rate is too high"
          description: "5-minute availability is {{ $value | humanizePercentage }}, SLO target is 99.95%"
          runbook_url: "https://wiki.example.com/runbooks/slo-burn-rate"
```

- **SLOBurnRateHigh** — Fires when 5-minute availability drops below 99.9% for 5 minutes. This is a burn rate alert — 99.9% over 5 minutes means the error budget would be exhausted in ~8 hours.

```yaml
      - alert: ErrorBudgetExhausted
        expr: slo:error_budget:remaining < 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Error budget is nearly exhausted"
          description: "Only {{ $value | humanizePercentage }} of error budget remaining"
```

- **ErrorBudgetExhausted** — Fires when less than 10% of the monthly error budget remains.

```yaml
      - alert: HighLatency
        expr: slo:api_latency:ratio_rate5m < 0.95
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "API latency SLO at risk"
          description: "Only {{ $value | humanizePercentage }} of requests are under 200ms"
```

- **HighLatency** — Fires when fewer than 95% of requests meet the 200ms latency target.

---

## 5. Verification Checklist

- [ ] Prometheus is running: `kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus`
- [ ] Prometheus targets are UP: access `/targets` in Prometheus UI
- [ ] SLO recording rules are active: `curl localhost:9090/api/v1/rules | jq '.data.groups[].name'`
- [ ] SLO metrics are being computed:
  ```bash
  curl 'localhost:9090/api/v1/query?query=slo:api_availability:ratio_rate5m'
  ```
- [ ] Grafana is accessible and shows data
- [ ] SLO dashboard imported and rendering correctly
- [ ] Loki is receiving logs: query `{namespace="production"}` in Grafana Explore
- [ ] Alertmanager is configured: `kubectl get secret alertmanager-monitoring-kube-prometheus-alertmanager -n monitoring`
- [ ] PagerDuty/Slack integration works (trigger a test alert)
- [ ] Jaeger shows distributed traces across services

---

## 6. Troubleshooting

### Prometheus targets showing DOWN

```bash
# Check the target's scrape config
kubectl get servicemonitor -n monitoring

# Verify the pod has the correct annotations
kubectl get pod <pod-name> -n production -o yaml | grep -A3 annotations

# Check Prometheus logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

### No data in Grafana dashboards

```bash
# Verify Prometheus data source is configured
# Grafana → Configuration → Data Sources → Prometheus → Test

# Check if metrics exist
# Prometheus UI → query: http_requests_total

# If no metrics, check if services are instrumented with Prometheus client
```

### Loki not receiving logs

```bash
# Check Promtail status
kubectl logs -n monitoring -l app=promtail

# Verify Promtail is discovering pods
# Promtail logs should show "targets" being scraped
```

### SLO alerts firing unexpectedly

```bash
# Check actual metric values
curl 'localhost:9090/api/v1/query?query=slo:api_availability:ratio_rate5m'

# Check if the 5xx rate has genuinely increased
curl 'localhost:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[5m])'

# If alerts are too sensitive, adjust the threshold or for duration
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **SLO-based vs. threshold alerts** | SLO-based | Static thresholds (CPU > 80%) | Alerts on user impact, not infrastructure metrics. Trade-off: requires SLI instrumentation. |
| **Prometheus vs. Datadog** | Prometheus | Datadog / New Relic | Open-source, Kubernetes-native, no per-host licensing. Trade-off: requires self-management. |
| **Loki vs. ELK** | Loki | Elasticsearch + Kibana | Lightweight, indexes only labels (not full text). Trade-off: less powerful text search. |
| **Burn rate alerts** | Multi-window burn rate | Simple threshold | Catches slow and fast error budget consumption. Trade-off: more complex to understand and configure. |
| **OpenTelemetry** | OTel SDK | Jaeger client / X-Ray SDK | Vendor-neutral, future-proof. Trade-off: still maturing in some language ecosystems. |

---

## 8. Production Considerations

- **Retention** — Configure Prometheus retention (15-30 days) and Loki retention to manage storage costs
- **Thanos/Cortex** — For long-term metric storage, add Thanos sidecar to Prometheus
- **High availability** — Run 2 Prometheus replicas with deduplication for alerting reliability
- **Alert fatigue** — Tune alert thresholds and `for` durations to minimize false positives; start with fewer alerts and add more as needed
- **Runbook links** — Every alert should include a `runbook_url` annotation linking to remediation steps
- **Dashboard as code** — Store Grafana dashboards in Git (JSON) and deploy via ConfigMaps
- **Cost** — Prometheus cardinality (unique time series) is the primary cost driver; monitor with `prometheus_tsdb_head_series`

---

## 9. Next Phase

**[Phase 9: Security & Compliance →](../phase-09-security/README.md)**

With full observability in place, Phase 9 locks down the platform with OPA/Gatekeeper admission policies, HashiCorp Vault for dynamic secrets, zero-trust network policies, and non-root container enforcement.

---

[← Phase 7: GitOps](../phase-07-gitops/README.md) | [Back to Project Overview](../README.md) | [Phase 9: Security →](../phase-09-security/README.md)
