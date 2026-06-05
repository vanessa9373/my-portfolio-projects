# Lab 13: Chaos Engineering & Resilience Testing (AWS FIS)

![AWS FIS](https://img.shields.io/badge/AWS_FIS-FF9900?style=flat&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)

## Summary (The "Elevator Pitch")

Designed a chaos engineering program using AWS Fault Injection Simulator and Litmus Chaos to proactively discover failure modes before they cause outages. Ran 8 types of experiments (instance stops, CPU stress, network latency, pod deletions), discovered 12 previously unknown failure modes, and improved recovery time by 40%.

## The Problem

The team **assumed** their systems were resilient because they had Multi-AZ deployments and auto-scaling. But they'd never actually tested what happens when an AZ goes down, a node runs out of disk, or network latency spikes. Every real incident was a surprise, and recovery was ad-hoc because no one had practiced it.

## The Solution

Built a **chaos engineering framework** with safety controls: a Python orchestrator validates steady-state before experiments, runs controlled failure injections (via AWS FIS or Litmus), monitors metrics throughout, and auto-stops if safety thresholds are breached. Game Day playbooks structure quarterly resilience testing sessions.

## Architecture

```
  ┌─────────────────────────────────────────────────────────┐
  │               Chaos Engineering Framework                │
  │                                                         │
  │  ┌─────────────┐       ┌─────────────────────────┐     │
  │  │  Experiment  │──────►│   Target Infrastructure  │     │
  │  │  Orchestrator│       │   (EKS / EC2 / RDS)     │     │
  │  │  (Python)    │       └─────────────────────────┘     │
  │  └──────┬──────┘                │                       │
  │         │                       ▼                       │
  │   ┌─────┴──────┐       ┌──────────────┐               │
  │   │ AWS FIS    │       │ Prometheus   │               │
  │   │ Litmus     │       │ (Monitoring) │               │
  │   │ Chaos      │       └──────┬───────┘               │
  │   └────────────┘              ▼                        │
  │                       ┌──────────────┐                 │
  │                       │   Grafana    │                 │
  │                       │ (Dashboard)  │                 │
  │                       └──────────────┘                 │
  │                                                        │
  │  Safety: CloudWatch Alarms → Auto Stop if breached     │
  └─────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| AWS FIS | AWS-native fault injection | Managed service, IAM-integrated, stop conditions |
| LitmusChaos | Kubernetes chaos experiments | Open-source, CRD-based, extensive experiment library |
| Python | Experiment orchestrator | Pre-checks, safety validation, result analysis |
| Prometheus | Real-time monitoring during experiments | Validates steady-state hypothesis |
| Grafana | Experiment dashboards | Visual impact analysis |

## Implementation Steps

### Step 1: Deploy Chaos Infrastructure
**What this does:** Sets up AWS FIS experiment templates, Litmus Chaos operator, and monitoring dashboards.
```bash
cd terraform && terraform init && terraform apply
```

### Step 2: Verify Monitoring is Healthy
**What this does:** Validates that Prometheus is scraping all targets and dashboards show steady-state before injecting any failures.
```bash
python scripts/run-experiment.py --pre-check
```

### Step 3: Run an Experiment
**What this does:** Executes a controlled chaos experiment with safety controls — pre-check → inject failure → monitor → auto-stop if thresholds breached.
```bash
# AWS FIS: Stop EC2 instance in one AZ
python scripts/run-experiment.py --experiment aws-fis/ec2-instance-stop --duration 300

# Litmus: Delete random pods
kubectl apply -f experiments/litmus/pod-delete.yaml
```

### Step 4: Analyze Results
**What this does:** Generates a report showing: what was tested, what happened (metrics during experiment), what we learned, and action items.
```bash
python scripts/analyze-results.py --experiment-id exp-20260101 --window 1h
```

### Step 5: Conduct Game Day
**What this does:** Runs a structured 4-hour resilience testing session with defined roles, safety protocols, and multiple experiments.

## Experiment Catalog

| ID | Experiment | Category | Blast Radius | Risk |
|----|-----------|----------|-------------|------|
| CE-01 | EC2 Instance Stop | Compute | Single AZ | Medium |
| CE-02 | CPU Stress (80%) | Compute | Single instance | Low |
| CE-03 | Network Latency (+200ms) | Network | Target group | Medium |
| CE-04 | Network Packet Loss (30%) | Network | Target group | High |
| CE-05 | Pod Delete | Kubernetes | Single pod | Low |
| CE-06 | Node Drain | Kubernetes | Single node | Medium |
| CE-07 | DNS Failure | Network | Namespace | High |
| CE-08 | Disk Fill (90%) | Storage | Single node | Medium |

## Project Structure

```
13-chaos-engineering-aws/
├── README.md
├── experiments/
│   ├── aws-fis/
│   │   └── ec2-instance-stop.json   # FIS template with stop conditions
│   └── litmus/
│       └── pod-delete.yaml          # LitmusChaos ChaosEngine
├── scripts/
│   ├── run-experiment.py            # Orchestrator: pre-check → inject → monitor → stop
│   └── analyze-results.py           # Post-experiment analysis and reporting
└── docs/
    └── gameday-playbook.md          # 4-hour Game Day: roles, agenda, safety protocols
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `scripts/run-experiment.py` | Validates steady-state, runs experiment, monitors metrics, auto-stops on threshold breach | Safety-first chaos engineering |
| `experiments/aws-fis/ec2-instance-stop.json` | FIS template: stops EC2 instances in a target AZ with CloudWatch stop conditions | AWS FIS, stop conditions, IAM |
| `experiments/litmus/pod-delete.yaml` | Litmus ChaosEngine: deletes random pods with steady-state probes | CRD-based chaos, Kubernetes |
| `docs/gameday-playbook.md` | 4-hour agenda: roles (facilitator, operator, observer), safety protocols, experiment sequence | Structured resilience testing |

## Results & Metrics

| Metric | Result |
|--------|--------|
| Failure Modes Discovered | **12** (previously unknown) |
| Recovery Time | **40% faster** after fixing discovered issues |
| Post-Program Availability | **99.99%** |
| Game Days Conducted | **4 per quarter** |

## How I'd Explain This in an Interview

> "The team assumed their multi-AZ setup was resilient because they'd never tested it. I built a chaos engineering program with a Python orchestrator that validates steady-state, injects controlled failures (instance stops, network latency, pod deletions), monitors metrics, and auto-stops if safety thresholds are breached. We discovered 12 failure modes we didn't know existed — like a service that crashed when its cache was unavailable because it had no fallback. After fixing those issues, recovery time improved 40% and we achieved 99.99% availability. We now run Game Days quarterly."

## Key Concepts Demonstrated

- **Chaos Engineering** — Proactively testing system resilience
- **Steady-State Hypothesis** — Validating normal behavior before and after experiments
- **Safety Controls** — Auto-stop when metrics breach thresholds
- **AWS FIS** — Managed fault injection with IAM-based targeting
- **LitmusChaos** — Kubernetes-native chaos experiments
- **Game Days** — Structured quarterly resilience testing sessions
- **Blast Radius Control** — Starting small, expanding gradually

## Lessons Learned

1. **Start small** — delete a single pod before stopping an entire AZ
2. **Safety controls are non-negotiable** — always have auto-stop conditions
3. **Test in production (carefully)** — staging can't replicate real traffic patterns
4. **Chaos reveals hidden dependencies** — you'll find services that fail without their cache, queue, or DNS
5. **Game Days build team confidence** — practicing recovery makes real incidents less stressful

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
