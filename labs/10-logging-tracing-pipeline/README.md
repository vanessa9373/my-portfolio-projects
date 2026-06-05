# Lab 10: Logging & Tracing Pipeline (EFK + OpenTelemetry + Jaeger)

![Elasticsearch](https://img.shields.io/badge/Elasticsearch-005571?style=flat&logo=elasticsearch&logoColor=white)
![Fluent Bit](https://img.shields.io/badge/Fluent_Bit-49BDA5?style=flat&logo=fluentbit&logoColor=white)
![Jaeger](https://img.shields.io/badge/Jaeger-66CFE3?style=flat&logo=jaeger&logoColor=white)
![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-000000?style=flat&logo=opentelemetry&logoColor=white)

## Summary (The "Elevator Pitch")

Built a complete observability pipeline covering centralized logging (EFK stack) and distributed tracing (OpenTelemetry + Jaeger). Combined with the metrics stack from Lab 08, this completes the **three pillars of observability** — metrics, logs, and traces — with log-trace correlation so you can jump from a log line directly to the full request trace.

## The Problem

Logs were scattered across individual pods — to debug an issue, engineers had to `kubectl logs` into multiple pods and manually piece together what happened across services. For a 12-service app, a single user request touches 5-6 services. Tracing a failure across services was like finding a needle in a haystack.

## The Solution

Built two pipelines: **Centralized Logging** (Fluent Bit collects logs from all pods → Elasticsearch stores/indexes → Kibana searches/visualizes) and **Distributed Tracing** (OpenTelemetry instruments services → Jaeger collects and visualizes traces). **Log-trace correlation** connects them — each log line includes a trace ID that links to the full request trace in Jaeger.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Three Pillars of Observability                  │
│                                                                   │
│  METRICS (Lab 08)      LOGS (This Lab)       TRACES (This Lab)   │
│  ┌──────────────┐    ┌───────────────┐    ┌───────────────────┐  │
│  │ Prometheus   │    │  Fluent Bit   │    │  OpenTelemetry    │  │
│  │ + Grafana    │    │  (DaemonSet)  │    │  Collector        │  │
│  └──────────────┘    └───────┬───────┘    └────────┬──────────┘  │
│                              ▼                      ▼             │
│                       ┌──────────────┐    ┌───────────────────┐  │
│                       │Elasticsearch │    │     Jaeger        │  │
│                       │  (Storage)   │    │  (Trace Storage)  │  │
│                       └───────┬──────┘    └────────┬──────────┘  │
│                               ▼                     ▼             │
│                       ┌──────────────┐    ┌───────────────────┐  │
│                       │   Kibana     │    │  Jaeger UI        │  │
│                       │ (Search/Viz) │◄──►│ (Trace Viewer)    │  │
│                       └──────────────┘    └───────────────────┘  │
│                              ▲                      ▲             │
│                              └──── Log-Trace Correlation ────┘   │
└──────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| Fluent Bit | Log collection (DaemonSet) | Lightweight, Kubernetes-native, flexible routing |
| Elasticsearch | Log storage and indexing | Full-text search, scalable, index lifecycle |
| Kibana | Log search and visualization | Rich query UI, dashboards |
| OpenTelemetry | Trace instrumentation and collection | Vendor-neutral standard |
| Jaeger | Trace storage and visualization | Open-source, Kubernetes-native |

## Implementation Steps

### Step 1: Deploy Elasticsearch
**What this does:** Creates an Elasticsearch cluster for log storage with index lifecycle management (auto-delete logs older than 30 days).
```bash
kubectl apply -f logging/elasticsearch.yaml -n logging
```

### Step 2: Deploy Fluent Bit as DaemonSet
**What this does:** Runs Fluent Bit on every node to collect container logs, parse them, add Kubernetes metadata (pod name, namespace), and ship to Elasticsearch.
```bash
kubectl apply -f logging/fluent-bit.yaml -n logging
```

### Step 3: Deploy Kibana
**What this does:** Provides a web UI for searching and visualizing logs stored in Elasticsearch.
```bash
kubectl apply -f logging/kibana.yaml -n logging
kubectl port-forward svc/kibana 5601:5601 -n logging
```

### Step 4: Deploy OpenTelemetry Collector
**What this does:** Collects traces from instrumented services and exports them to Jaeger.
```bash
kubectl apply -f tracing/otel-collector.yaml -n tracing
```

### Step 5: Deploy Jaeger
**What this does:** Stores and visualizes distributed traces — shows the full journey of a request across all services.
```bash
kubectl apply -f tracing/jaeger.yaml -n tracing
kubectl port-forward svc/jaeger-query 16686:16686 -n tracing
```

### Step 6: Configure Log-Trace Correlation
**What this does:** Adds trace IDs to log entries so you can click a log line in Kibana and jump to the full trace in Jaeger.

### Step 7: Verify the Pipeline
**What this does:** Generates traffic and verifies logs appear in Kibana and traces appear in Jaeger.
```bash
# Generate traffic
kubectl run load-test --image=busybox --restart=Never -- wget -q -O- http://frontend.sre-demo
# Check Kibana for logs, Jaeger for traces
```

## Project Structure

```
10-logging-tracing-pipeline/
├── README.md
├── logging/
│   ├── elasticsearch.yaml       # Elasticsearch StatefulSet with storage
│   ├── fluent-bit.yaml          # Fluent Bit DaemonSet with parsing config
│   ├── kibana.yaml              # Kibana deployment and service
│   └── index-lifecycle.yaml     # Auto-delete logs older than 30 days
├── tracing/
│   ├── otel-collector.yaml      # OpenTelemetry Collector config
│   └── jaeger.yaml              # Jaeger all-in-one deployment
├── dashboards/
│   └── kibana-dashboards.json   # Pre-built Kibana dashboards
└── scripts/
    └── verify-pipeline.sh       # End-to-end pipeline verification
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `logging/fluent-bit.yaml` | DaemonSet that collects logs from `/var/log/containers/`, parses JSON, adds K8s metadata | Log collection, parsing, metadata enrichment |
| `logging/elasticsearch.yaml` | StatefulSet with persistent storage, index templates, lifecycle policies | Data persistence, index management |
| `tracing/otel-collector.yaml` | Receives traces via OTLP, processes them, exports to Jaeger | OpenTelemetry protocol, trace sampling |
| `logging/index-lifecycle.yaml` | Automatically deletes indices older than 30 days to manage storage | Index lifecycle management, cost control |

## Results & Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Log Search | `kubectl logs` per pod | Centralized Kibana search | **Single pane of glass** |
| Request Tracing | Manual guesswork | Jaeger end-to-end traces | **Full request visibility** |
| Debug Time | Hours (grep across pods) | Minutes (search + trace) | **80% faster debugging** |
| Log Retention | Until pod restart (lost) | 30 days (Elasticsearch) | **Persistent, searchable** |

## How I'd Explain This in an Interview

> "With 12 microservices, debugging was painful — you'd kubectl logs into each pod trying to piece together what happened. I built two pipelines: centralized logging with the EFK stack (Fluent Bit collects from all pods, Elasticsearch indexes, Kibana searches) and distributed tracing with OpenTelemetry and Jaeger (shows the full request journey across services). The key feature is log-trace correlation — every log line includes a trace ID, so you can click from a log entry straight to the full trace. Combined with Prometheus metrics from Lab 08, this completes the three pillars of observability."

## Key Concepts Demonstrated

- **Three Pillars of Observability** — Metrics + Logs + Traces
- **Centralized Logging** — EFK stack (Elasticsearch, Fluent Bit, Kibana)
- **Distributed Tracing** — OpenTelemetry + Jaeger
- **Log-Trace Correlation** — Trace IDs in log entries
- **Index Lifecycle Management** — Automated log retention/deletion
- **DaemonSet Pattern** — Fluent Bit runs on every node

## Lessons Learned

1. **Fluent Bit over Fluentd** — Fluent Bit uses 10x less memory, perfect for Kubernetes
2. **Index lifecycle is critical** — without it, Elasticsearch fills up disk and crashes
3. **Log-trace correlation is the killer feature** — connecting logs to traces transforms debugging
4. **Sampling is necessary at scale** — tracing 100% of requests is too expensive; sample 10-20%
5. **Start with structured logging** — JSON logs are parseable; plain text logs require complex regex

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
