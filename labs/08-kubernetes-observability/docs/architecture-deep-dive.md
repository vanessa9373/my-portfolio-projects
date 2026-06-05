# Lab 08: Kubernetes Observability Platform — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** Google SRE Three Pillars of Observability  
> **Scope:** Full monitoring stack for 12-service microservices app — Prometheus + Grafana + Alertmanager + HPA + NetworkPolicies

---

## What This Platform Solves

Zero visibility means zero confidence. A team that can't answer "is the application healthy?" can't answer "is it safe to deploy?" — so they don't deploy, which means they accumulate changes, which makes the next deployment riskier. An observability platform breaks this cycle: you know what's happening, so you can act on it.

---

## Architecture: The Three Pillars

```
Microservices (12 services in sre-demo namespace)
        │
        ├── Metrics ─────────────────► Prometheus (collect) → Grafana (visualize)
        │                                                    → Alertmanager (alert)
        │
        ├── Logs  ──────────────────► (Lab 10: EFK stack)
        │
        └── Traces ─────────────────► (Lab 10: Jaeger)
```

This lab covers the metrics pillar. Logs and traces are in Lab 10.

---

## Step-by-Step: Observability Stack Deployment

### Step 1 — Local Multi-Node Cluster with k3d

```bash
k3d cluster create sre-demo \
  --servers 1 \
  --agents 3 \
  --port 8080:80@loadbalancer \
  --image rancher/k3s:v1.28.4-k3s1
```

**Why k3d instead of minikube?**  
minikube runs a single-node cluster. k3d creates a multi-node cluster (1 server + 3 agents) matching production topology — pods can be spread across agents, node drains are testable, and DaemonSets deploy to each node separately. Observability behavior (Prometheus scraping, node exporter metrics) is realistic in multi-node; single-node hides issues like "Prometheus can't reach pods on other nodes."

**Why 3 agents?**  
3 agents correspond to 3 AZs in production. Testing that Prometheus scrapes pods across all nodes validates that service discovery works correctly. With 1 node, every pod is on the same node — you'd never discover that Prometheus can't reach pods in different subnets/AZs.

### Step 2 — Deploy Online Boutique Microservices

```bash
kubectl create namespace sre-demo
kubectl apply -f microservices-demo/kubernetes-manifests/ -n sre-demo
```

The 12 services form a complete dependency chain:
```
User → frontend → (productcatalogservice, cartservice, checkoutservice)
                       │                      │
                       └── redis-cart         └── (paymentservice, shippingservice, emailservice)
                                                        │
                                                  currencyservice, recommendationservice, adservice
```

**Why use Google Online Boutique specifically?**  
Most observability tutorials use a single hello-world service. Online Boutique provides:
- 12 services with real service-to-service dependencies
- Multiple languages (Go, Python, Java, C#, Node.js) — different memory/CPU profiles
- A load generator (Locust) that produces realistic traffic patterns
- Already has Prometheus metrics endpoints in most services

Observability on a single service doesn't teach anything about cross-service correlation, which is where observability becomes valuable.

### Step 3 — kube-prometheus-stack Helm Deployment

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
  --set grafana.adminPassword=prom-operator
```

**Why `kube-prometheus-stack` (formerly `prometheus-operator`) instead of standalone Prometheus?**  

Standalone Prometheus requires:
1. Manual YAML configuration file
2. Manual restart when configuration changes
3. No auto-discovery of new Kubernetes services
4. No Grafana bundled
5. No Alertmanager bundled

`kube-prometheus-stack` provides:
- **ServiceMonitor and PodMonitor CRDs:** Define what Prometheus should scrape as Kubernetes resources — no YAML config file editing
- **Auto-discovery:** New services that match a ServiceMonitor selector are automatically scraped — no Prometheus restart
- **Pre-built dashboards:** Grafana ships with 20+ built-in Kubernetes dashboards
- **Pre-configured alerts:** AlertManager rules for common Kubernetes issues
- **Operator pattern:** Configuration changes applied without Prometheus restart

**Why `retention=15d`?**  
Prometheus stores metrics in time-series format on local disk. Longer retention = more disk. 15 days covers:
- Last 2 weeks of incidents for investigation
- Enough history for weekly trend analysis
- Two full business cycles (Prometheus is not for long-term metrics storage — use Thanos or Cortex for that)

### Step 4 — Custom Alerting Rules

```yaml
# alerts/pod-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-demo-alerts
  namespace: monitoring
  labels:
    release: prometheus  # ← must match the Helm release name for discovery
spec:
  groups:
    - name: pod-health
      rules:
        - alert: HighErrorRate
          expr: |
            rate(http_requests_total{
              namespace="sre-demo",
              status=~"5.."
            }[5m]) > 0.01
          for: 5m      # sustained for 5 minutes before alerting
          labels:
            severity: critical
          annotations:
            summary: "High error rate on {{ $labels.job }}"
            description: "Error rate is {{ $value | humanizePercentage }}"
        
        - alert: PodCrashLooping
          expr: |
            rate(kube_pod_container_status_restarts_total{
              namespace="sre-demo"
            }[15m]) > 0
          for: 5m
          labels:
            severity: warning
        
        - alert: HighCPUUsage
          expr: |
            sum(rate(container_cpu_usage_seconds_total{
              namespace="sre-demo",
              container!=""
            }[5m])) by (pod) > 0.8
          for: 10m
          labels:
            severity: warning
        
        - alert: NodeDiskPressure
          expr: kube_node_status_condition{condition="DiskPressure",status="true"} == 1
          for: 1m
          labels:
            severity: critical
```

**Why `for: 5m` on the high error rate alert?**  
A single spike in error rate could be a brief traffic anomaly — a single bad request, a brief dependency restart. Requiring 5 consecutive minutes of elevated error rate ensures the alert fires for persistent problems, not transient blips. This is the `evaluation_periods = 2` equivalent in AWS CloudWatch terms.

**Why `labels: release: prometheus` on the PrometheusRule?**  
Prometheus Operator discovers PrometheusRule resources by matching labels against the `ruleSelector` in the Prometheus CR. The `kube-prometheus-stack` Helm chart sets `ruleSelector: matchLabels: { release: prometheus }` by default. Without this label, the PrometheusRule is created but silently ignored by Prometheus — one of the most common configuration mistakes.

### Step 5 — Horizontal Pod Autoscaler

```bash
# CPU-based HPA for the frontend service
kubectl autoscale deployment frontend \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n sre-demo
```

**Why HPA requires resource requests:**  
HPA calculates utilization as:
```
utilization = actual_cpu / requested_cpu
```
If `requested_cpu` is 0 (not set), this formula produces division by zero — HPA cannot compute utilization and will not scale. The Online Boutique manifests include resource requests for all services; this is not an accident.

**HPA controller algorithm:**
```
desired_replicas = ceil(current_replicas × (current_metric / desired_metric))
```
Example: 2 replicas, CPU at 140%, target 70%:
```
desired = ceil(2 × (140 / 70)) = ceil(4) = 4
```
HPA scales to 4 replicas. If CPU then drops to 40%:
```
desired = ceil(4 × (40 / 70)) = ceil(2.28) = 3
```
HPA scales to 3 (with a scale-down cooldown to prevent thrashing).

### Step 6 — Network Policies

```yaml
# network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: sre-demo
spec:
  podSelector: {}    # applies to all pods
  policyTypes:
    - Ingress
    - Egress
---
# network-policies/app-policies.yaml — allow frontend to backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: sre-demo
spec:
  podSelector:
    matchLabels:
      app: productcatalogservice
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 3550
```

**Critical ordering: apply allow rules BEFORE the deny-all**  
Applying `default-deny-all` first immediately breaks all service-to-service communication. The Online Boutique stops working entirely. The correct order:
1. Apply all allow rules (`kubectl apply -f app-policies.yaml`)
2. Verify services still work
3. Apply the deny-all (`kubectl apply -f default-deny.yaml`)
4. Only communication matching allow rules survives

**Why NetworkPolicies when Kubernetes RBAC already exists?**  
RBAC controls who can call the Kubernetes API (deploy pods, create secrets). NetworkPolicies control what network traffic pods can send and receive. These are orthogonal security controls. A compromised `productcatalogservice` pod with no network policy can open a TCP connection to `checkoutservice`'s port — even though the application doesn't intend this communication path. NetworkPolicies prevent this lateral movement.

### Step 7 — Accessing Grafana Dashboards

```bash
# Port-forward Grafana
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

# Default credentials: admin / prom-operator (set via --set grafana.adminPassword)
```

**Pre-built dashboards available in kube-prometheus-stack:**
- **Kubernetes / Compute Resources / Cluster:** Node CPU/memory utilization
- **Kubernetes / Compute Resources / Namespace:** Pod resource usage per namespace
- **Kubernetes / Networking / Cluster:** Network in/out per pod
- **Node Exporter / Nodes:** Disk, CPU, memory, network per node

**Why rely on pre-built dashboards first?**  
The kube-prometheus-stack maintainers have spent years refining these dashboards. Starting from pre-built and customizing is faster and produces better dashboards than starting from blank. The pre-built dashboards also serve as PromQL examples — studying them teaches the query language.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **ServiceMonitor CRDs:** New services are scraped automatically when labeled correctly — no manual Prometheus configuration updates
- **Pre-built dashboards:** Operational visibility in minutes, not days of dashboard building
- **PrometheusRule as code:** Alert rules version-controlled alongside application code — alert changes are reviewed and auditable

### Security
- **NetworkPolicies:** Compromised pod cannot access arbitrary services — lateral movement blocked
- **Monitoring namespace isolation:** Prometheus and Grafana in a separate namespace — application namespaces can't reach monitoring infrastructure directly

### Reliability
- **HPA auto-scaling:** Service survives traffic spikes without manual intervention
- **Prometheus scraping:** Every service is monitored — no silent failures
- **`for: 5m` on alerts:** Transient spikes don't page the on-call; sustained degradations do

### Performance Efficiency
- **kube-prometheus-stack recording rules:** Pre-computed aggregations reduce query time for dashboards
- **15-day retention:** Enough for incident analysis without excessive disk use

### Cost Optimization
- **k3d local cluster:** No cloud compute cost for learning and testing observability patterns
- **15-day retention:** Prometheus is not a time-series database for long-term storage — bounded retention prevents disk growth

### Sustainability
- **HPA scale-down:** Unused capacity removed — no idle pods consuming compute resources

---

## Key Architectural Insight

The shift from reactive to proactive monitoring is not about the tools — it's about what you measure. Measuring "is CPU high?" is reactive: you find out a problem happened. Measuring "is error rate within SLO?" is proactive: you find out if a problem is happening before users notice. The kube-prometheus-stack makes collecting the right metrics easy; the harder work is defining what "healthy" looks like (SLIs) and writing alerts that fire only when "healthy" is threatened.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
