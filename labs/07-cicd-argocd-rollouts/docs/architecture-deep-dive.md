# Lab 07: CI/CD with ArgoCD & Argo Rollouts — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** Progressive delivery — canary deployments with automated Prometheus-backed analysis and auto-rollback

---

## What This Architecture Solves

Standard Kubernetes rolling updates treat all users equally: when a new version deploys, all users get it simultaneously. If it has a bug, all users experience it. Canary deployment changes this model: new versions get a small traffic slice first, and automated analysis decides whether to proceed or rollback — entirely without human intervention. The blast radius of a bad deploy drops from 100% of users to 10%.

---

## The Progressive Delivery Model

```
Standard Rolling Update:
  v1 → v1 → v1     # t=0: all stable
  v2 → v1 → v1     # t=1: 33% new (unvalidated)
  v2 → v2 → v1     # t=2: 67% new (unvalidated)
  v2 → v2 → v2     # t=3: 100% new

Argo Rollouts Canary:
  v1 → v1 → v1 → v1 → v1 → v1    # t=0: stable
  v2 → v1 → v1 → v1 → v1 → v1    # t=1: 10% (1/6 pods)
  Prometheus analysis: error rate 0.2% < 1% threshold ✓
  v2 → v2 → v1 → v1 → v1 → v1    # t=2: 30% (2/6 pods)
  Prometheus analysis: p99 latency 180ms < 500ms threshold ✓
  v2 → v2 → v2 → v2 → v2 → v2    # t=3: 100% promoted
```

---

## Step-by-Step: Canary Rollout Configuration

### Step 1 — Argo Rollouts Resource

```yaml
# argocd/rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 6
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      containers:
        - name: myapp
          image: myapp:stable  # updated by CI
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
  
  strategy:
    canary:
      steps:
        - setWeight: 10          # 10% of traffic to canary
        - pause:
            duration: 5m         # analyze for 5 minutes
        - analysis:              # query Prometheus
            templates:
              - templateName: success-rate
              - templateName: latency-p99
        - setWeight: 30          # 30% to canary
        - pause:
            duration: 5m
        - analysis:
            templates:
              - templateName: success-rate
              - templateName: latency-p99
        - setWeight: 100         # full promotion
      
      trafficRouting:
        nginx:
          stableIngress: myapp-stable
```

**Why 5-minute analysis windows?**  
Traffic patterns have statistical noise. A 30-second window may show zero errors simply because traffic volume is too low to produce statistically significant results. Five minutes at 10% traffic provides enough requests (at 100 req/s total → 10 req/s canary = 3,000 requests over 5 minutes) to distinguish real error rate changes from noise.

**Why 10% → 30% → 100% steps (not 10% → 50% → 100%)?**  
A 50% canary step means half of all users experience the new version if it's buggy. The 10% → 30% step sequence minimizes blast radius while providing progressively larger samples for analysis. If the 10% step passes (low traffic, potentially low confidence), the 30% step provides higher confidence before full promotion.

### Step 2 — AnalysisTemplate for Prometheus-backed Decisions

```yaml
# argocd/analysis-templates.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
    - name: success-rate
      interval: 1m                    # query every 1 minute
      successCondition: result[0] >= 0.99  # 99% success rate required
      failureLimit: 2                 # allow 2 failures before abort
      provider:
        prometheus:
          address: http://prometheus-operated:9090
          query: |
            sum(rate(http_requests_total{
              job="myapp",
              status!~"5..",
              version="{{args.canary-hash}}"
            }[2m])) /
            sum(rate(http_requests_total{
              job="myapp",
              version="{{args.canary-hash}}"
            }[2m]))
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency-p99
spec:
  metrics:
    - name: latency-p99
      interval: 1m
      successCondition: result[0] <= 0.5  # p99 must be <= 500ms
      failureLimit: 2
      provider:
        prometheus:
          address: http://prometheus-operated:9090
          query: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket{
                job="myapp",
                version="{{args.canary-hash}}"
              }[2m])) by (le)
            )
```

**Why `failureLimit: 2` instead of `failureLimit: 0`?**  
A single anomalous Prometheus scrape (missing data, network hiccup) can return 0 or NaN for a metric. With `failureLimit: 0`, one missed scrape immediately aborts the rollout. With `failureLimit: 2`, the analysis requires 3 consecutive failures before aborting — distinguishing a real degradation (persistent failures) from transient monitoring noise.

**Why query by `version` label on the canary pods?**  
During a canary rollout, both stable and canary pods are running simultaneously. Without filtering by version, the Prometheus query returns aggregated metrics across both versions — the 90% stable traffic dilutes the 10% canary signal. The `version="{{args.canary-hash}}"` filter isolates metrics to only the canary pods, making the analysis accurate.

**The auto-rollback flow:**
```
Canary at 10%, 5-minute analysis window
    │
Prometheus query: success-rate = 0.97 (below 0.99 threshold)
    │
AnalysisRun records: FAILURE (1 of 2)
    │
Prometheus query (1 minute later): success-rate = 0.96
    │
AnalysisRun records: FAILURE (2 of 2)
    │
failureLimit exceeded → AnalysisRun status: FAILED
    │
Argo Rollouts: abort rollout, setWeight(0), scale canary to 0
    │
All traffic back to stable v1
    │
Slack/PagerDuty alert: "Rollout myapp aborted due to high error rate"
```

Total time from bad deploy to full rollback: ~2 minutes (1 minute per failure × 2 failures). Users impacted: 10% for ~7 minutes (5-minute analysis window + 2 minutes of failures).

### Step 3 — Helm Charts for Multi-Environment Deployment

```yaml
# helm/values-production.yaml
replicaCount: 6
image:
  repository: ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/myapp
  tag: "latest"  # overridden by CI

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi

rollout:
  strategy: canary
  steps:
    - weight: 10
    - pause: { duration: 5m }
    - weight: 30
    - pause: { duration: 5m }
    - weight: 100

analysis:
  successRateThreshold: 0.99
  latencyP99ThresholdMs: 500
  failureLimit: 2

pdb:
  enabled: true
  minAvailable: 4  # never have fewer than 4 pods available (6 total)
```

**Why PodDisruptionBudget with `minAvailable: 4` out of 6?**  
During a Kubernetes node drain (cluster upgrade, node replacement), the cluster evicts pods to reschedule them. Without a PDB, all 6 pods could be evicted simultaneously — zero availability. With `minAvailable: 4`, at most 2 pods can be unavailable simultaneously. This ensures:
- During node drain: service maintains at least 67% capacity
- During canary with 1 pod down: still have 5 of 6 pods serving

**Why separate `values-staging.yaml` and `values-production.yaml`?**  
Different environments have different risk tolerances. Staging configuration:
```yaml
# helm/values-staging.yaml
replicaCount: 2         # smaller footprint
rollout:
  steps:
    - weight: 50        # aggressive canary in staging — faster testing
    - pause: { duration: 1m }
    - weight: 100
pdb:
  enabled: false        # allow full restart in staging
```

Staging can fail loudly and recover. Production must fail safely and gracefully.

### Step 4 — GitHub Actions CD Pipeline

```yaml
# github-actions/cd-pipeline.yaml
- name: Update Helm values with new image tag
  run: |
    cd helm/
    yq eval ".image.tag = \"${{ github.sha }}\"" -i values.yaml
    git add values.yaml
    git commit -m "cd: deploy image ${{ github.sha }}"
    git push

- name: Trigger ArgoCD sync
  run: |
    argocd app sync myapp \
      --revision HEAD \
      --timeout 300 \
      --grpc-web
```

**Why update Helm values.yaml instead of the deployment manifest directly?**  
Helm values are semantic — `image.tag` clearly communicates intent. Direct manifest updates (sed on deployment.yaml) are brittle — a reformatting of the YAML can break the sed pattern. More importantly, `values.yaml` is the canonical Helm interface. ArgoCD renders Helm templates with the updated values, giving you full Helm-managed lifecycle (pre-upgrade hooks, release history, rollback via Helm).

### Step 5 — Rollback Automation

```bash
# scripts/rollback.sh
#!/bin/bash
set -e

ROLLOUT_NAME=${1:-myapp}

echo "Aborting rollout: $ROLLOUT_NAME"
kubectl argo rollouts abort $ROLLOUT_NAME

echo "Waiting for rollback to complete..."
kubectl argo rollouts status $ROLLOUT_NAME --timeout=300s

echo "Verifying pod health..."
kubectl get pods -l app=$ROLLOUT_NAME

# Notify team
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-type: application/json' \
  --data "{\"text\": \"🚨 Rollout for $ROLLOUT_NAME aborted and rolled back to stable version\"}"
```

**Why Slack notification in the rollback script?**  
Automated rollbacks can happen silently. Engineers may not notice a deployment was aborted unless they check ArgoCD. A Slack notification ensures the team is aware that:
1. A deployment was attempted
2. It failed analysis
3. It was automatically rolled back
4. Investigation is required

Without notification, an automated rollback is invisible — and the root cause goes uninvestigated, likely causing the same failure on the next deploy.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Automated deployment decisions:** Argo Rollouts replaces human judgment with data — no "it looks okay" deployments
- **Helm multi-env values:** Same chart, different risk profiles per environment — no per-environment forks
- **Rollback script with notification:** Automated rollback is visible to the team, not silent

### Security
- **canary-hash label filtering:** Analysis queries are scoped to canary pods — no metric pollution from stable traffic
- **ArgoCD auth:** `argocd app sync` uses an ArgoCD service account with minimal permissions — no cluster-admin required

### Reliability
- **PodDisruptionBudget:** At least 4/6 pods available during any disruption — voluntary and involuntary
- **failureLimit: 2:** Transient monitoring noise doesn't abort deployments; sustained degradation does
- **Automated rollback < 2 minutes:** Faster than any on-call engineer can respond at 2am

### Performance Efficiency
- **10% canary for initial analysis:** Real production traffic validates performance without exposing all users
- **Prometheus-based p99 analysis:** Catches latency regressions, not just error rates — catches slow deploys that don't fail

### Cost Optimization
- **Canary prevents expensive rollback costs:** A bad deploy to 100% of users may require hot-fixes, incident responses, customer compensation. Canary limits exposure to 10% of users.
- **Reduced incident costs:** Automated rollback eliminates the 30-minute MTTR during business hours for caught regressions

### Sustainability
- **Reduced incident-driven overtime:** Automated rollback at 2am prevents engineer wakeups for preventable incidents

---

## Key Architectural Insight

The canary + automated analysis pattern represents a fundamental shift in deployment philosophy: from **human-approved** ("looks good, promote") to **data-approved** ("metrics meet thresholds, auto-promote"). Human approval doesn't scale — it's sequential and subjective. Data approval is parallel (analysis runs continuously) and objective (success rate either meets the threshold or it doesn't). The result is that deployment decisions are made faster and with higher confidence than any human reviewer can provide.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
