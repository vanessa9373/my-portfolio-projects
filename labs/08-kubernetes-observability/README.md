# Lab 08: Kubernetes Observability Platform

![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat&logo=grafana&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)

## Summary (The "Elevator Pitch")

Built a production-grade Kubernetes observability platform for a 12-service microservices application (Google Online Boutique). Deployed Prometheus for metrics, Grafana for dashboards, Alertmanager for notifications, HPA for auto-scaling, and NetworkPolicies for security — the complete monitoring stack you'd find at companies like Google or Netflix.

## The Problem

A microservices application with 12 services was running on Kubernetes, but the team had **zero visibility** into what was happening. They couldn't answer basic questions: "Is the app healthy? Which service is slow? Are we running out of resources?" When things broke, they only found out when users complained.

## The Solution

Built a complete observability stack: **Prometheus** scrapes metrics from every pod, **Grafana** visualizes them in dashboards, **Alertmanager** sends notifications when things go wrong, **HPA** auto-scales pods based on CPU, and **NetworkPolicies** control pod-to-pod communication. Now the team sees problems before users do.

## Architecture

```
                        +-------------------+
                        |   Load Balancer   |
                        +--------+----------+
                                 |
                    +------------+------------+
                    |            |            |
              +-----+----+ +----+----+ +-----+----+
              | Worker-0 | | Worker-1| | Worker-2 |
              +----------+ +---------+ +----------+

    Namespace: sre-demo (12 microservices)
    ┌─────────────────────────────────────────────────┐
    │ frontend │ cart │ checkout │ currency │ email    │
    │ payment  │ product-catalog │ recommendation     │
    │ shipping │ ad │ redis-cart │ load-generator     │
    └─────────────────────────────────────────────────┘

    Namespace: monitoring
    ┌─────────────────────────────────────────────────┐
    │ Prometheus │ Grafana │ Alertmanager             │
    └─────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| k3d (k3s in Docker) | Lightweight local K8s cluster | Simulates production without cloud costs |
| Google Online Boutique | 12-service microservices app | Real-world complexity, multiple languages |
| Prometheus | Metrics collection and storage | Industry standard for Kubernetes monitoring |
| Grafana | Dashboards and visualization | Rich dashboards, Prometheus data source |
| Alertmanager | Alert routing and notification | Groups alerts, routes to Slack/PagerDuty |
| HPA | Auto-scaling pods | CPU/memory-based scaling |
| NetworkPolicy | Pod-to-pod traffic control | Zero-trust network security |

## Implementation Steps

### Step 1: Create Kubernetes Cluster
**What this does:** Creates a local multi-node Kubernetes cluster using k3d with 1 server and 3 worker nodes.
```bash
k3d cluster create sre-demo --servers 1 --agents 3 --port 8080:80@loadbalancer
```

### Step 2: Deploy Microservices Application
**What this does:** Deploys the Google Online Boutique — 12 interconnected microservices (frontend, cart, checkout, payment, etc.).
```bash
kubectl create namespace sre-demo
kubectl apply -f microservices-demo/kubernetes-manifests/ -n sre-demo
kubectl get pods -n sre-demo   # Verify all 12 services are running
```

### Step 3: Install Prometheus Stack
**What this does:** Deploys Prometheus (metrics collection), Grafana (dashboards), and Alertmanager (notifications) using the kube-prometheus-stack Helm chart.
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### Step 4: Configure Alerting Rules
**What this does:** Applies custom PrometheusRules — alerts for high error rates, pod restarts, high CPU, node disk pressure, and more.
```bash
kubectl apply -f alerts/pod-alerts.yaml -n monitoring
```

### Step 5: Access Grafana Dashboards
**What this does:** Port-forwards Grafana to your local machine where you can view pre-built dashboards for cluster and application health.
```bash
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# Open http://localhost:3000 (admin/prom-operator)
```

### Step 6: Configure Auto-Scaling
**What this does:** Sets up Horizontal Pod Autoscaler to automatically scale pods when CPU exceeds 70%.
```bash
kubectl autoscale deployment frontend --cpu-percent=70 --min=2 --max=10 -n sre-demo
```

### Step 7: Apply Network Policies
**What this does:** Restricts pod-to-pod communication — frontend can only talk to specific backend services, not directly to the database.
```bash
kubectl apply -f network-policies/ -n sre-demo
```

## Project Structure

```
08-kubernetes-observability/
├── README.md
├── SRE-Project1-Summary.md          # Detailed walkthrough with troubleshooting
├── microservices-demo/              # Google Online Boutique (12 services)
│   └── kubernetes-manifests/        # All deployment YAML files
├── alerts/
│   └── pod-alerts.yaml              # Custom PrometheusRule alerting
├── monitoring/                      # Prometheus/Grafana configurations
└── network-policies/                # NetworkPolicy YAML files
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `microservices-demo/kubernetes-manifests/` | All 12 microservice deployments, services, and configs | Microservices architecture, service mesh |
| `alerts/pod-alerts.yaml` | PrometheusRules: high error rate, pod restarts, CPU/memory alerts | PromQL queries, alert thresholds |
| `SRE-Project1-Summary.md` | 556-line detailed walkthrough with every command, error, and fix | Real-world troubleshooting, SRE practices |

## Results & Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Visibility | Zero (no monitoring) | Full observability | **Complete visibility** |
| Alert Response | Reactive (user complaints) | Proactive (Prometheus alerts) | **Find issues before users** |
| Scaling | Manual pod scaling | Automatic HPA | **Auto-scaling on CPU** |
| Network Security | All pods can talk to all pods | NetworkPolicy isolation | **Zero-trust networking** |

## How I'd Explain This in an Interview

> "I set up a complete observability platform for a 12-service microservices app on Kubernetes. Before this, the team had zero visibility — they only found out about problems when users complained. I deployed Prometheus for metrics, Grafana for dashboards, and Alertmanager for notifications, plus HPA for auto-scaling and NetworkPolicies for security. The detailed walkthrough in this project documents every step including the troubleshooting — things like Prometheus not scraping because of missing service monitors, pods failing because of incorrect resource limits. In SRE, the troubleshooting is where the real learning happens."

## Key Concepts Demonstrated

- **Three Pillars of Observability** — Metrics (Prometheus), Logs, Traces
- **Kubernetes Monitoring** — kube-prometheus-stack deployment
- **Custom Alerting** — PrometheusRules with PromQL
- **Auto-Scaling** — HPA based on CPU utilization
- **Network Security** — NetworkPolicies for pod isolation
- **Microservices Architecture** — 12-service application deployment
- **Real-World Troubleshooting** — Documented errors and fixes

## Lessons Learned

1. **Start with default dashboards** — kube-prometheus-stack includes excellent built-in Grafana dashboards
2. **Resource requests are required for HPA** — pods without CPU requests can't be auto-scaled
3. **NetworkPolicies are deny-by-default** — once you apply the first policy, all other traffic is blocked
4. **Prometheus needs service monitors** — pods without ServiceMonitor labels won't be scraped
5. **Document your troubleshooting** — future you (and your team) will thank you

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
