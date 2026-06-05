# Lab 14: Chaos Engineering with LitmusChaos — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + Principles of Chaos Engineering  
> **Scope:** Kubernetes-native chaos framework — pod-delete, CPU stress, network latency, node drain, resilience scorecard

---

## What This Framework Solves

Kubernetes restarts failed pods automatically. This is self-healing. It is not the same as resilience. Self-healing restarts a pod after it dies; resilience means the application continues serving requests while the pod is being restarted. Those are different properties, and a cluster can have the first without the second. LitmusChaos tests the second: does the application maintain acceptable behavior while Kubernetes is doing its self-healing work?

---

## Architecture: Hypothesis-Driven Kubernetes Chaos

```
LitmusChaos Operator (installed in litmus namespace)
         │
         └── Watches ChaosEngine CRDs in target namespaces
                   │
                   ├── Pre-experiment: Steady-State Probes
                   │     ├── HTTP probe: /health returns 200
                   │     └── Prometheus probe: error_rate < 1%
                   │
                   ├── Fault Injection
                   │     ├── pod-delete: delete random pods in target namespace
                   │     ├── pod-cpu-hog: stress CPU to 80% in target pods
                   │     ├── pod-network-latency: tc netem +200ms on eth0
                   │     └── node-drain: cordon + evict all pods from one node
                   │
                   └── Post-experiment: Steady-State Probes
                         └── Same probes as pre-experiment
                               └── Result: Passed (hypothesis confirmed) or
                                          Failed (resilience gap found)
```

---

## Step-by-Step: LitmusChaos Framework

### Step 1 — LitmusChaos Operator Installation

```bash
# Install Litmus CRDs and operator
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v2.14.0.yaml

# Verify operator is running
kubectl get pods -n litmus
# Expected: chaos-operator-ce-xxx   Running   litmus
```

**Why LitmusChaos over writing bash scripts that kill pods directly?**  
A bash script that runs `kubectl delete pod` is a chaos experiment with no safety controls, no hypothesis validation, no result recording, and no automatic cleanup if the experiment is interrupted. LitmusChaos adds all of these: the ChaosEngine CRD defines the experiment declaratively, the operator validates steady-state probes before and after, ChaosResult CRDs record the outcome, and cleanup jobs restore normal state even if the experiment is manually stopped. Chaos experiments need the same rigor as any other operational procedure.

### Step 2 — Steady-State Hypothesis Probes

```yaml
# steady-state/probes.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: pod-delete-engine
  namespace: sre-demo
spec:
  appinfo:
    appns: sre-demo
    applabel: app=frontend
  
  # Steady-state validation: must pass before AND after experiment
  experiments:
    - name: pod-delete
      spec:
        probe:
          # HTTP probe: app must respond
          - name: health-check
            type: httpProbe
            httpProbe/inputs:
              url: http://frontend.sre-demo/health
              insecureSkipVerify: false
              responseTimeout: 2000  # 2 seconds max response time
              method:
                get:
                  criteria: "==200"
                  responseCode: "200"
            mode: Continuous
            runProperties:
              probeTimeout: 5s
              interval: 5s
              retry: 1
          
          # Prometheus probe: error rate must stay within SLO
          - name: slo-check
            type: promProbe
            promProbe/inputs:
              endpoint: http://prometheus:9090
              query: |
                sum(rate(http_requests_total{namespace="sre-demo", status=~"5.."}[2m]))
                /
                sum(rate(http_requests_total{namespace="sre-demo"}[2m])) * 100
              comparator:
                type: float
                criteria: "<="
                value: "1.0"  # error rate must stay below 1%
            mode: Edge  # check at start and end only
```

**Why Continuous mode for HTTP probes vs Edge mode for Prometheus probes?**  
Continuous mode checks every 5 seconds throughout the experiment — it's appropriate for a liveness check (is the app responding at all?) because any single failure matters. Edge mode checks only at the start and end — it's appropriate for a rate metric because a 2-minute rate window can't be meaningfully measured every 5 seconds (the rate computation period is longer than the sampling interval). Mismatching probe mode to metric type produces misleading results.

**Why define both HTTP and Prometheus probes?**  
The HTTP probe catches hard failures (service is down, returning 5xx for every request). The Prometheus probe catches soft failures (service is responding but at degraded SLO). A service could pass the HTTP probe (health endpoint returns 200) while failing the Prometheus probe (main API endpoints are timing out). Both probes together ensure the steady-state hypothesis is comprehensive.

### Step 3 — Pod Delete Experiment

```yaml
# experiments/pod-delete.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: pod-delete-engine
  namespace: sre-demo
spec:
  jobCleanUpPolicy: delete  # clean up experiment pods after completion
  
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "60"          # delete pods for 60 seconds
            - name: CHAOS_INTERVAL
              value: "10"          # delete 1 pod every 10 seconds
            - name: FORCE
              value: "false"       # graceful deletion (SIGTERM, not SIGKILL)
            - name: PODS_AFFECTED_PERC
              value: "50"          # affect 50% of target pods
```

**Why `FORCE: false` (graceful deletion) rather than SIGKILL?**  
A graceful deletion sends SIGTERM to the pod, which allows the application to finish in-flight requests, close database connections, and drain work from queues before terminating. SIGKILL terminates immediately without cleanup — which tests a different failure mode (OOM kill, hardware failure) than a graceful pod rotation (rolling deploy, node drain). Using `FORCE: false` tests that the application handles graceful shutdown correctly, which is the more common case.

**Why `PODS_AFFECTED_PERC: 50` rather than a fixed count?**  
A fixed count (delete 2 pods) means different blast radius for different deployments. If the service has 2 replicas, deleting 2 means 100% impact. If it has 10, deleting 2 means 20%. Percentage-based targeting maintains consistent relative blast radius regardless of current replica count.

**Result: pod-delete score = 95/100**  
Recovery time was 12 seconds against a 60-second target. All probes passed throughout. Score deduction: occasional brief p99 latency spike to 280ms (above 200ms SLO) during the deletion window.

### Step 4 — Network Latency Experiment

```yaml
# experiments/network-latency.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
spec:
  experiments:
    - name: pod-network-latency
      spec:
        components:
          env:
            - name: NETWORK_LATENCY
              value: "200"         # inject 200ms latency
            - name: JITTER
              value: "20"          # ±20ms jitter (realistic network behavior)
            - name: TOTAL_CHAOS_DURATION
              value: "120"
            - name: TARGET_CONTAINER
              value: "cartservice"
            - name: DESTINATION_IPS
              value: ""            # applies to all outbound traffic
            - name: NETWORK_INTERFACE
              value: "eth0"
```

**Why add 200ms of latency specifically?**  
200ms is the p99 latency target for Tier 1 services. Injecting 200ms tests what happens when *one hop* in the dependency chain reaches the SLO boundary. In a 5-service request chain, if each service calls the next with 200ms latency, the end-to-end latency is 1 second — which would fail the overall SLO. Testing with 200ms reveals whether services have appropriate timeout budgets for their position in the call chain.

**Finding: cart service fails with 200ms latency (score 72/100)**  
The cart service had a 150ms timeout on its call to the product catalog service. Under 200ms injected latency, every catalog call timed out — causing the cart to return errors to users even though the catalog service was healthy. This revealed a timeout budget allocation error: the outer service timeout was less than the injected latency, making failure certain.

**Action item from this finding:** Cart service timeout increased from 150ms to 500ms (to allow for realistic downstream latency), and retry logic added with exponential back-off.

### Step 5 — Resilience Scorecard

```bash
#!/bin/bash
# scripts/generate-scorecard.sh

echo "=== Resilience Scorecard ==="
echo

for experiment in pod-delete cpu-stress network-latency network-loss node-drain; do
    # Query ChaosResult CRD
    result=$(kubectl get chaosresult ${experiment} -n sre-demo -o json)
    
    verdict=$(echo $result | jq -r '.status.experimentStatus.verdict')
    probe_success=$(echo $result | jq -r '.status.experimentStatus.probeSuccessPercentage')
    
    echo "Experiment: $experiment"
    echo "  Verdict: $verdict"
    echo "  Probe Success: ${probe_success}%"
    echo
done
```

| Experiment | Score | Key Finding |
|-----------|-------|-------------|
| Pod Delete | 95/100 | Recovery in 12s (target: 60s) — robust self-healing |
| CPU Stress 80% | 88/100 | Latency degraded but within SLO; HPA responded in 2m |
| Network +200ms | 72/100 | **Cart service timeout too tight — needs retry logic** |
| Node Drain | 90/100 | All pods rescheduled in 45s across remaining nodes |
| Packet Loss 30% | 65/100 | **Payment service has no circuit breaker** |

**Why a numerical score rather than pass/fail?**  
Pass/fail treats "error rate reached 0.9% (threshold 1%)" as equivalent to "error rate reached 0.1%" — both pass. A score reflects the margin. A service scoring 65/100 on packet loss is technically passing but has minimal headroom. The score makes prioritization concrete: services with scores below 75 get reliability work before the next Game Day, services above 90 are considered mature for that failure mode.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **ChaosResult CRDs stored in Kubernetes:** Experiment results are queryable with `kubectl get chaosresult` — no separate tool needed to review findings
- **Resilience scorecard drives backlog:** Below-75 scores create immediate engineering tickets — findings are not just observations but actionable work items
- **Declarative experiments in Git:** ChaosEngine manifests are version-controlled — experiment configuration changes are reviewed and auditable

### Security
- **Namespace-scoped experiments:** Litmus operates only in the `sre-demo` namespace — cannot affect monitoring, logging, or other namespaces
- **RBAC for chaos operator:** The Litmus service account has permission to delete pods in target namespaces but cannot modify Secrets or ConfigMaps
- **Graceful termination:** `FORCE: false` ensures experiments simulate realistic failure modes rather than destructive hardware-equivalent terminations

### Reliability
- **Steady-state probes as gatekeepers:** Experiments that fail pre-probes are aborted — no failure is injected into an already-degraded system
- **Continuous HTTP probes:** Any experiment causing the health endpoint to fail immediately registers in the probe results — failure detection within 5 seconds
- **Findings become fixes:** 72/100 for network latency led to timeout reconfiguration and retry logic that improved resilience in production

### Performance Efficiency
- **Percentage-based blast radius:** `PODS_AFFECTED_PERC: 50` maintains consistent relative impact regardless of current replica count
- **`jobCleanUpPolicy: delete`:** Experiment pods are cleaned up automatically — no resource accumulation from frequent test runs

### Cost Optimization
- **Litmus is open-source:** No licensing cost for the chaos framework; resource cost is only the experiment pods (short-lived, seconds to minutes)
- **Finding issues in staging vs production:** A timeout misconfiguration found via chaos engineering costs developer hours; the same misconfiguration found during a real production incident costs revenue and customer trust

### Sustainability
- **Targeted experiments:** Chaos is applied to specific pods/nodes with explicit scope — entire cluster is not stressed for single-service experiments

---

## Key Architectural Insight

The most important finding from Litmus experiments is never the obvious failure mode — it's the hidden assumption. The cart service scored 72/100 not because it lacked retry logic (the team knew retries should be added someday) but because the timeout value was hardcoded at 150ms — less than the latency being injected. No one had noticed because in production, the catalog service always responded in 80ms. The team was one bad deploy away from discovering this in a real incident. LitmusChaos found it in a Game Day. The value of chaos engineering is not testing resilience — it's making visible the assumptions embedded in code that have never been questioned because the happy path always worked.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
