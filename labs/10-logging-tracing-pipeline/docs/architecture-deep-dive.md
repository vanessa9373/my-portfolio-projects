# Lab 10: Logging & Tracing Pipeline — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** Three Pillars of Observability (completing the trilogy from Lab 08/09)  
> **Scope:** EFK stack (centralized logging) + OpenTelemetry + Jaeger (distributed tracing) + log-trace correlation

---

## What This Pipeline Solves

Metrics tell you that something is wrong (error rate spiked). Logs tell you what happened on each service (request received, database timeout). Traces tell you the complete story of a single request across all services (user added to cart → checkout called → payment failed at step 3 of 5). Without all three, debugging a distributed system means guessing. With all three and log-trace correlation, you can click from a Grafana alert to a Kibana log to a Jaeger trace in seconds.

---

## Architecture: The Three Pillars Together

```
Lab 08: Metrics → Prometheus → Grafana
                                  │
Lab 09: SLOs → Alertmanager → PagerDuty
                                  │
Lab 10: Logs  → Fluent Bit → Elasticsearch → Kibana     ─┐
                                                           ├─ Correlated via Trace ID
        Traces → OTel Collector → Jaeger ───────────────  ┘
```

---

## Step-by-Step: Centralized Logging (EFK Stack)

### Step 1 — Elasticsearch StatefulSet

```yaml
# logging/elasticsearch.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: logging
spec:
  replicas: 1  # single-node for lab; production uses 3-node cluster
  serviceName: elasticsearch
  template:
    spec:
      containers:
        - name: elasticsearch
          image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
          env:
            - name: discovery.type
              value: single-node
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
            - name: xpack.security.enabled
              value: "false"  # simplified for lab; enable for production
          
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
  
  volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

**Why StatefulSet for Elasticsearch (not Deployment)?**  
Elasticsearch is a stateful application — it stores indexed data on disk and each node has a stable identity in the cluster. StatefulSets provide:
- Stable, persistent pod names (`elasticsearch-0`, `elasticsearch-1`) used for cluster formation
- Ordered deployment and deletion (Elasticsearch must form a quorum before accepting writes)
- Per-pod persistent volumes (each pod gets its own PVC, not shared storage)

A Deployment would assign random pod names and provide shared-or-no persistent storage — both incompatible with Elasticsearch's clustering model.

**Why `ES_JAVA_OPTS: -Xms512m -Xmx512m` (same value for min and max)?**  
Setting heap min = max prevents JVM from growing and shrinking the heap dynamically. Heap resize in a JVM pauses all threads (stop-the-world GC). For a production log indexer, a JVM pause causes Fluent Bit's connection to Elasticsearch to time out and buffered logs to be retried. Fixed heap eliminates this GC pause risk. For the lab, 512MB is sufficient; production typically allocates 50% of instance memory to Elasticsearch heap (never more than 32GB — JVM compressed pointer limit).

### Step 2 — Fluent Bit DaemonSet

```yaml
# logging/fluent-bit.yaml
apiVersion: apps/v1
kind: DaemonSet  # ← one pod per node
metadata:
  name: fluent-bit
  namespace: logging
spec:
  template:
    spec:
      serviceAccountName: fluent-bit  # needs list/watch access to pods
      
      volumes:
        - name: varlog
          hostPath:
            path: /var/log  # node-level log directory
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers  # container log files
      
      containers:
        - name: fluent-bit
          image: fluent/fluent-bit:2.2.0
          
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
          
          # Fluent Bit configuration (ConfigMap-mounted)
          volumeMounts:
            - name: fluent-bit-config
              mountPath: /fluent-bit/etc/

# Fluent Bit ConfigMap:
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         5
        Log_Level     info
    
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        multiline.parser  docker, cri
        Tag               kube.*
        DB                /var/log/flb_kube.db  # position tracking DB
    
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_URL            https://kubernetes.default.svc:443
        Merge_Log           On     # parse JSON logs into fields
        Keep_Log            Off    # remove raw log after parsing
        K8S-Logging.Parser  On     # use pod annotation for log format
        K8S-Logging.Exclude Off
    
    [OUTPUT]
        Name  es
        Match *
        Host  elasticsearch.logging
        Port  9200
        Index fluentbit
        Logstash_Format On      # creates daily indices: fluentbit-2026.06.05
        Logstash_Prefix fluentbit
```

**Why Fluent Bit over Fluentd?**  
Fluentd is written in Ruby with a C core — it consumes ~40MB RAM per instance. Fluent Bit is written in pure C — it consumes ~1MB RAM per instance. On a 10-node cluster, this difference is 400MB vs 10MB for the log collection layer. Fluent Bit also starts faster (important during node restarts when log collection should resume immediately) and processes logs faster. Fluentd has a larger plugin ecosystem; Fluent Bit is sufficient for standard Kubernetes log collection.

**Why `DB: /var/log/flb_kube.db`?**  
Fluent Bit reads log files by position. Without a position database, if Fluent Bit restarts (pod eviction, node restart), it re-reads all log files from the beginning — sending duplicate logs to Elasticsearch. The position database records the last read offset in each log file. On restart, Fluent Bit resumes from where it left off — no duplicates.

**Why `multiline.parser: docker, cri`?**  
Kubernetes writes container logs in two formats depending on the container runtime:
- Docker: `{"log": "...", "stream": "stdout", "time": "..."}`
- CRI (containerd): plain text with a prefix

The multiline parser handles both formats and correctly reassembles multiline log messages (Java stack traces, Python tracebacks) into a single Elasticsearch document rather than separate lines.

### Step 3 — Index Lifecycle Management

```yaml
# logging/index-lifecycle.yaml
# PUT _ilm/policy/fluentbit-policy (Elasticsearch API)
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "1d",      # create new index daily
            "max_size": "5gb"     # or when size exceeds 5GB
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 }
        }
      },
      "delete": {
        "min_age": "30d",         # delete after 30 days
        "actions": { "delete": {} }
      }
    }
  }
}
```

**Why Index Lifecycle Management is non-negotiable in production:**  
Without ILM, Elasticsearch indices grow indefinitely. A 12-service application logging 100MB/day fills 36GB in a year. At $0.10/GB/month on SSD, that's $3.60/month. More critically: Elasticsearch query performance degrades as indices grow — large indices require more JVM heap and slower query planning. ILM rolling creates new indices daily (each day's logs in a separate index), moves older indices to warm storage (single shard, merged segments = smaller, faster to query), and deletes old indices automatically.

**Why 30-day retention?**  
30 days covers:
- Last month's incidents for investigation
- SOC 2 audit requirements (many standards require 30-day log retention minimum)
- Enough history to distinguish normal patterns from anomalies

---

## Step-by-Step: Distributed Tracing (OpenTelemetry + Jaeger)

### Step 4 — OpenTelemetry Collector

```yaml
# tracing/otel-collector.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317  # gRPC OTLP
          http:
            endpoint: 0.0.0.0:4318  # HTTP OTLP
    
    processors:
      batch:                   # batch traces before exporting (efficiency)
        timeout: 1s
        send_batch_size: 1024
      
      memory_limiter:          # prevent OOM under high trace volume
        check_interval: 1s
        limit_mib: 400
    
    exporters:
      jaeger:
        endpoint: jaeger-collector.tracing:14250  # gRPC to Jaeger
        tls:
          insecure: true
      
      logging:                 # debug exporter for development
        loglevel: debug
    
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [jaeger]
```

**Why OpenTelemetry Collector instead of direct SDK → Jaeger?**  
Direct instrumentation (SDK sends spans directly to Jaeger) creates a tight coupling between application code and the backend. If you switch from Jaeger to Tempo or Zipkin, you must update every service's instrumentation. The OTel Collector is a vendor-neutral proxy:
- Applications export to the collector via OTLP (standard protocol)
- The collector forwards to any backend (Jaeger, Tempo, Zipkin, AWS X-Ray)
- Switching backends requires updating one collector config, not every service

**Why `memory_limiter` processor?**  
If the Jaeger backend is slow or unavailable, the OTel Collector buffers traces in memory. Without a memory limit, this buffer can grow to consume all available container memory → OOM kill → trace collection stops. The `memory_limiter` drops traces when memory pressure is high — better to drop some traces than to crash the collector entirely.

**Why `batch` processor?**  
Sending one span at a time means one HTTP/gRPC request per span. At 1,000 requests/second × 5 spans per request = 5,000 individual Jaeger writes per second. Batching groups 1,024 spans into one Jaeger write — 5,000 writes becomes ~5 writes. Dramatically reduces network overhead and Jaeger ingestion load.

### Step 5 — Jaeger Backend

```yaml
# tracing/jaeger.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
spec:
  template:
    spec:
      containers:
        - name: jaeger
          image: jaegertracing/all-in-one:1.52
          env:
            - name: SPAN_STORAGE_TYPE
              value: memory  # ephemeral for lab; badger or Elasticsearch for production
            - name: QUERY_BASE_PATH
              value: /jaeger
          ports:
            - containerPort: 14250  # gRPC collector (receives from OTel)
            - containerPort: 16686  # UI
            - containerPort: 14268  # HTTP collector (legacy)
```

**Why `all-in-one` for the lab vs separate components for production?**  
`jaegertracing/all-in-one` bundles the collector, query, and UI in a single container — simpler for development and learning. Production uses separate deployments:
- `jaeger-collector`: receives spans (can be scaled horizontally)
- `jaeger-query`: serves the UI and API (stateless, can be scaled)
- Elasticsearch or Cassandra for span storage (not in-memory)

In-memory storage is ephemeral (spans lost on restart) but sufficient for understanding the architecture.

### Step 6 — Log-Trace Correlation

The killer feature: connecting a log line to the full trace.

**How it works:**

Application code adds the current trace ID to every log entry:
```python
# Python example (OpenTelemetry instrumented)
from opentelemetry import trace
import logging

logger = logging.getLogger(__name__)

def process_order(order_id):
    span = trace.get_current_span()
    trace_id = format(span.get_span_context().trace_id, '032x')
    
    logger.info(
        "Processing order",
        extra={
            "trace_id": trace_id,
            "order_id": order_id
        }
    )
    # ... processing logic
```

Fluent Bit ships the log (including `trace_id`) to Elasticsearch.

In Kibana:
1. Search for logs from a failed request: `status:500 AND service:checkout`
2. Find the log entry with `trace_id: abc123def456...`
3. Click the trace ID link → opens Jaeger with the full trace

**Why this changes debugging fundamentally:**  
Without trace IDs in logs, debugging a failure means:
- Find the error in Kibana (which service? which request?)
- Note the timestamp
- Go to Jaeger, search by service and time range
- Find the relevant trace (one of hundreds at that timestamp)

With trace IDs in logs:
- Find the error in Kibana
- Click the trace ID
- Immediately see the full 12-service request chain with latency per service

The debugging process goes from 30 minutes to 2 minutes.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Log-trace correlation:** Reduces MTTR by 80% — direct path from symptom to root cause
- **ILM automated index management:** Log retention enforced automatically, no manual cleanup
- **OTel Collector as abstraction:** Backend can change without application code changes

### Security
- **Read-only Fluent Bit volume mounts:** Log collection doesn't require write access to log files
- **Fluent Bit ServiceAccount:** Minimal RBAC — only `list` and `watch` on pods, not `get secrets`
- **Network isolation:** Elasticsearch and Jaeger in dedicated `logging`/`tracing` namespaces, reachable only from authorized services

### Reliability
- **Fluent Bit position database:** No log duplication on restart
- **OTel batch processor:** Collector survives backend slowness without OOMing
- **ILM prevents disk exhaustion:** Elasticsearch doesn't fill the node's disk

### Performance Efficiency
- **Fluent Bit 1MB RAM:** Negligible overhead per node vs Fluentd's 40MB
- **Elasticsearch shard merging in warm phase:** Reduced memory footprint, faster queries on older data
- **OTel batch processor:** 99% fewer Jaeger writes at equivalent trace volume

### Cost Optimization
- **30-day ILM deletion:** Bounded storage cost regardless of log volume growth
- **Fluent Bit efficiency:** Lower resource usage = smaller node size required for DaemonSet overhead

### Sustainability
- **ILM tiering to warm storage:** Older data merged and compressed — less storage, less energy for persistence
- **Batch export:** Fewer network round trips for the same trace volume — lower network overhead

---

## Key Architectural Insight

The three pillars of observability (metrics, logs, traces) are not three tools — they are three different lenses on the same event. A failed checkout is:
- A metric spike: `error_rate{service="checkout"}` increases
- A set of log entries: each service logs what it tried to do
- A trace: the complete call graph showing exactly which service call failed and why

Log-trace correlation is the glue that makes these three lenses work together rather than requiring you to manually correlate timestamps across three different interfaces. The trace ID is the foreign key that joins the log table to the trace table.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
