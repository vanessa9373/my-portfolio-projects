# Lab 14: Chaos Engineering with Litmus Chaos

![LitmusChaos](https://img.shields.io/badge/LitmusChaos-2496ED?style=flat&logo=cncf&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)

## Summary (The "Elevator Pitch")

Built a Kubernetes-native chaos engineering framework using Litmus Chaos. Injected controlled failures — pod kills, CPU stress, network disruption, and node drains — with steady-state validation, automatic blast radius control, and a resilience scorecard that quantifies how well each service recovers from failures.

## The Problem

Kubernetes provides self-healing (restarts failed pods), but teams blindly trusted it without testing. Questions like "What happens if 3 pods die at once?" or "Can our app handle 200ms network latency?" were answered with "probably fine." In reality, many services failed silently or took too long to recover.

## The Solution

Implemented **Litmus Chaos** as a Kubernetes-native chaos framework. Each experiment defines a **steady-state hypothesis** (what "normal" looks like), injects a specific failure, then validates whether the system returns to steady-state within a time limit. A **resilience scorecard** tracks scores across experiments to quantify overall system reliability.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Chaos Engineering Workflow                    │
│                                                              │
│  1. Define Hypothesis     2. Inject Failure                 │
│  ┌─────────────────┐     ┌──────────────────┐              │
│  │ "App responds   │     │ Kill 3 pods      │              │
│  │  in < 200ms     │     │ Add 200ms latency│              │
│  │  with 0 errors" │     │ Stress CPU to 80%│              │
│  └────────┬────────┘     └────────┬─────────┘              │
│           │                       │                          │
│           ▼                       ▼                          │
│  3. Monitor + Validate   4. Score Results                   │
│  ┌─────────────────┐     ┌──────────────────┐              │
│  │ Prometheus checks│     │ Resilience Score │              │
│  │ steady-state     │     │ Pod Kill: 95/100 │              │
│  │ during & after   │     │ CPU: 88/100      │              │
│  └─────────────────┘     │ Network: 72/100   │              │
│                          └──────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| LitmusChaos | Kubernetes-native chaos experiments | CRD-based, extensive experiment hub |
| Prometheus | Steady-state monitoring during experiments | Validates hypothesis with PromQL |
| Grafana | Experiment impact visualization | Real-time dashboard during chaos |
| Bash | Experiment orchestration scripts | Lightweight, scriptable |

## Implementation Steps

### Step 1: Install Litmus Chaos Operator
**What this does:** Deploys the Litmus ChaosOperator and CRDs (Custom Resource Definitions) that enable chaos experiments as Kubernetes resources.
```bash
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v2.14.0.yaml
kubectl get pods -n litmus   # Verify operator is running
```

### Step 2: Install Chaos Experiments
**What this does:** Installs the experiment library — pod-delete, pod-cpu-hog, pod-network-latency, node-drain, etc.
```bash
kubectl apply -f https://hub.litmuschaos.io/api/chaos/2.14.0?file=charts/generic/experiments.yaml
```

### Step 3: Run Pod Delete Experiment
**What this does:** Randomly kills pods and validates that Kubernetes restarts them and the app recovers within 60 seconds.
```bash
kubectl apply -f experiments/pod-delete.yaml
kubectl describe chaosresult pod-delete -n sre-demo
```

### Step 4: Run CPU Stress Experiment
**What this does:** Stresses CPU to 80% on target pods and checks if the app maintains acceptable latency.
```bash
kubectl apply -f experiments/cpu-stress.yaml
```

### Step 5: Run Network Latency Experiment
**What this does:** Injects 200ms network latency between services and validates the app handles it gracefully.
```bash
kubectl apply -f experiments/network-latency.yaml
```

### Step 6: Run Node Drain Experiment
**What this does:** Drains a worker node (evicts all pods) and verifies they reschedule on other nodes.
```bash
kubectl apply -f experiments/node-drain.yaml
```

### Step 7: Generate Resilience Scorecard
**What this does:** Aggregates results from all experiments into a resilience score per service.
```bash
./scripts/generate-scorecard.sh
```

## Project Structure

```
14-chaos-engineering-litmus/
├── README.md
├── experiments/
│   ├── pod-delete.yaml              # Random pod deletion with recovery validation
│   ├── cpu-stress.yaml              # CPU stress test (80% utilization)
│   ├── network-latency.yaml         # 200ms injected latency
│   ├── network-loss.yaml            # 30% packet loss
│   ├── node-drain.yaml              # Worker node drain and reschedule
│   └── disk-fill.yaml               # Disk usage to 90%
├── steady-state/
│   └── probes.yaml                  # Prometheus probes for hypothesis validation
├── scripts/
│   ├── run-all-experiments.sh       # Sequential experiment runner
│   └── generate-scorecard.sh        # Resilience scorecard generator
└── docs/
    └── gameday-playbook.md          # Game Day facilitation guide
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `experiments/pod-delete.yaml` | ChaosEngine: deletes random pods, validates recovery < 60s | Steady-state probes, blast radius |
| `experiments/network-latency.yaml` | Injects 200ms latency via tc (traffic control) | Network chaos, latency tolerance |
| `steady-state/probes.yaml` | PromQL probes: error rate < 1%, p99 latency < 500ms | Hypothesis testing, PromQL |
| `scripts/generate-scorecard.sh` | Collects ChaosResult CRDs and generates a summary score | Resilience quantification |

## Results & Metrics

| Experiment | Resilience Score | Finding |
|-----------|-----------------|---------|
| Pod Delete | 95/100 | Recovery in 12s (target: 60s) |
| CPU Stress 80% | 88/100 | Latency degraded but within SLO |
| Network +200ms | 72/100 | Cart service timeout — needs retry logic |
| Node Drain | 90/100 | All pods rescheduled in 45s |
| Packet Loss 30% | 65/100 | Payment service failures — needs circuit breaker |

## How I'd Explain This in an Interview

> "Teams assumed Kubernetes self-healing was enough, but nobody had tested it. I set up Litmus Chaos to run controlled experiments — pod kills, CPU stress, network latency, node drains. Each experiment has a steady-state hypothesis (e.g., 'error rate stays below 1%') that's validated with Prometheus probes. We discovered that the cart service timed out under 200ms latency because it had no retry logic, and the payment service failed under packet loss because it lacked a circuit breaker. The resilience scorecard quantifies reliability per service, making it easy to prioritize fixes."

## Key Concepts Demonstrated

- **Chaos Engineering Methodology** — Hypothesis → inject → observe → learn
- **LitmusChaos CRDs** — Kubernetes-native chaos experiments
- **Steady-State Hypothesis** — Defining and validating "normal" behavior
- **Resilience Scorecard** — Quantifying reliability across services
- **Blast Radius Control** — Targeting specific pods/nodes/namespaces
- **Game Day Framework** — Structured team resilience testing

## Lessons Learned

1. **Missing retry logic is the #1 finding** — most services fail under network latency
2. **Circuit breakers prevent cascading failures** — without them, one slow service takes down everything
3. **Resilience scores drive prioritization** — scores < 75 get fixed before the next Game Day
4. **Start in non-production** — run experiments in staging before production
5. **Litmus CRDs make chaos declarative** — experiments are version-controlled like any other K8s resource

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
