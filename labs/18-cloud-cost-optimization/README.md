# Lab 18: Cloud Cost Optimization (FinOps)

![AWS](https://img.shields.io/badge/AWS-FF9900?style=flat&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)

## Summary (The "Elevator Pitch")

Built a comprehensive FinOps framework for AWS and Kubernetes — cost visibility dashboards, automated budget alerts, rightsizing recommendations, spot instance strategies, and idle resource detection. Demonstrated how SRE teams reduce cloud spend by 30-60% while maintaining reliability through data-driven cost governance.

## The Problem

Cloud costs were growing 20% month-over-month with no visibility into where money was going. Teams over-provisioned "just in case," idle resources ran 24/7, nobody used Reserved Instances or Spot, and there were no budget alerts. The monthly AWS bill was a surprise every time. Engineering had no cost accountability.

## The Solution

Implemented a **FinOps framework** across 4 pillars: **Visibility** (Cost Explorer dashboards, CUR reports, tagging strategy), **Governance** (budget alerts, spending limits, approval workflows), **Rightsizing** (Lambda-based analyzer that recommends instance right-sizing), and **Spot Strategy** (mixed instance policies for non-critical workloads). Kubernetes-specific optimizations include resource quotas, limit ranges, and Kubecost integration.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cost Optimization Stack                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Cost Explorer │  │   AWS CUR    │  │  Anomaly Detection   │  │
│  │  Dashboard    │  │  S3 Reports  │  │  (Auto-alert)        │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │               │
│         └─────────────────┼──────────────────────┘               │
│                           ▼                                      │
│                  ┌─────────────────┐                             │
│                  │  Budget Alerts  │──► SNS ──► Slack / Email   │
│                  │  (Per-team)     │                              │
│                  └─────────────────┘                             │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ Rightsizing       │  │  Spot Strategy   │                    │
│  │ Lambda Analyzer   │  │  Mixed Instances │                    │
│  │ (Auto-recommend)  │  │  (Non-critical)  │                    │
│  └──────────────────┘  └──────────────────┘                    │
│                                                                  │
│  Kubernetes:                                                     │
│  ┌───────────────┐  ┌──────────────┐  ┌──────────────────┐     │
│  │ Resource Quotas│  │ Limit Ranges │  │ Idle Resource    │     │
│  │ (Per namespace)│  │ (Per pod)    │  │ Detector (script)│     │
│  └───────────────┘  └──────────────┘  └──────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| AWS Cost Explorer | Cost visualization and forecasting | Built-in, no extra cost |
| AWS Budgets | Budget alerts and thresholds | Per-team, per-service budgets |
| AWS CUR | Detailed cost and usage reports | Line-item billing data in S3 |
| Lambda | Rightsizing analysis automation | Serverless, scheduled execution |
| Spot Instances | Cost reduction for non-critical workloads | 60-90% savings vs on-demand |
| Kubernetes Resource Quotas | Per-namespace spending limits | Prevents teams from over-provisioning |
| Bash Scripts | Idle resource detection | Finds unused EBS, EIPs, load balancers |

## Implementation Steps

### Step 1: Set Up Cost Visibility
**What this does:** Enables Cost Explorer, configures CUR (Cost and Usage Reports) to S3, and sets up the cost anomaly detection service.
```bash
cd terraform/cost-monitoring
terraform init && terraform apply
```

### Step 2: Configure Budget Alerts
**What this does:** Creates per-team and per-service budgets with alerts at 80%, 90%, and 100% thresholds. Alerts go to Slack and email.
```bash
cd ../budget-alerts
terraform init && terraform apply
```

### Step 3: Deploy Rightsizing Analyzer
**What this does:** Deploys a Lambda function that runs weekly, analyzes EC2 instance utilization via CloudWatch metrics, and recommends downsizing underutilized instances.
```bash
cd ../rightsizing
terraform init && terraform apply
```

### Step 4: Implement Spot Strategy
**What this does:** Configures mixed instance Auto Scaling Groups — on-demand for baseline capacity, spot instances for burst capacity (60-90% savings).
```bash
cd ../spot-strategy
terraform init && terraform apply
```

### Step 5: Apply Kubernetes Cost Controls
**What this does:** Sets resource quotas (CPU/memory limits per namespace) and limit ranges (defaults for pods that don't specify resources) to prevent over-provisioning.
```bash
kubectl apply -f policies/resource-quotas.yaml
kubectl apply -f policies/limit-ranges.yaml
```

### Step 6: Find Idle Resources
**What this does:** Scans for unused resources — unattached EBS volumes, unused Elastic IPs, idle load balancers, and stopped EC2 instances.
```bash
./scripts/idle-resource-detector.sh
```

### Step 7: Generate Cost Report
**What this does:** Produces a cost analysis report with per-service breakdown, trending, and optimization recommendations.
```bash
./scripts/cost-analysis.sh
./scripts/k8s-cost-report.sh
```

## Project Structure

```
18-cloud-cost-optimization/
├── README.md
├── terraform/
│   ├── cost-monitoring/
│   │   ├── main.tf              # Cost Explorer, CUR, anomaly detection
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── budget-alerts/
│   │   ├── main.tf              # AWS Budgets with SNS alerts
│   │   └── variables.tf
│   ├── rightsizing/
│   │   ├── main.tf              # Lambda rightsizing analyzer
│   │   ├── variables.tf
│   │   └── lambda/
│   │       └── index.py         # Rightsizing analysis logic
│   └── spot-strategy/
│       ├── main.tf              # Mixed instance ASG (on-demand + spot)
│       └── variables.tf
├── policies/
│   ├── resource-quotas.yaml     # Per-namespace CPU/memory limits
│   └── limit-ranges.yaml        # Default pod resource requests/limits
├── dashboards/
│   └── cost-dashboard.json      # Grafana cost visibility dashboard
└── scripts/
    ├── idle-resource-detector.sh # Find unused EBS, EIPs, ELBs
    ├── k8s-cost-report.sh       # Kubernetes namespace cost breakdown
    └── cost-analysis.sh         # AWS cost analysis and trending
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `terraform/budget-alerts/main.tf` | Creates AWS Budgets per team/service with 80/90/100% threshold alerts | Budget governance, SNS integration |
| `terraform/rightsizing/lambda/index.py` | Analyzes CloudWatch metrics to find over-provisioned instances | CloudWatch API, utilization analysis |
| `terraform/spot-strategy/main.tf` | Mixed instance ASG: on-demand base + spot burst capacity | Spot instances, capacity-optimized allocation |
| `policies/resource-quotas.yaml` | Kubernetes ResourceQuota: max CPU/memory per namespace | Kubernetes cost governance |
| `scripts/idle-resource-detector.sh` | Finds unattached EBS, unused EIPs, idle ELBs, stopped instances | Resource cleanup, waste elimination |

## Results & Metrics

| Optimization | Savings |
|-------------|---------|
| Rightsizing over-provisioned instances | **20-30%** per instance |
| Spot instances for non-critical workloads | **60-90%** vs on-demand |
| Deleting idle resources | **$2,000-5,000/month** |
| Kubernetes resource quotas | **Prevents over-provisioning** |
| Budget alerts | **No more surprise bills** |
| **Total Estimated Savings** | **30-60% reduction** |

## How I'd Explain This in an Interview

> "Cloud costs were growing 20% month-over-month with no visibility. I implemented a FinOps framework across 4 pillars: visibility (Cost Explorer dashboards, CUR reports), governance (per-team budget alerts at 80/90/100%), rightsizing (a Lambda function that analyzes CloudWatch metrics weekly and recommends downsizing under-utilized instances), and spot strategy (mixed instance ASGs for non-critical workloads at 60-90% savings). On the Kubernetes side, I applied resource quotas per namespace and limit ranges per pod to prevent over-provisioning. An idle resource detector script finds waste — unused EBS volumes, elastic IPs, and stopped instances. Together these optimizations reduce spend by 30-60%."

## Key Concepts Demonstrated

- **FinOps Framework** — Visibility, Governance, Rightsizing, Optimization
- **Budget Governance** — Per-team alerts prevent surprise bills
- **Rightsizing Automation** — Lambda-based utilization analysis
- **Spot Instances** — 60-90% savings for fault-tolerant workloads
- **Kubernetes Cost Controls** — Resource quotas and limit ranges
- **Idle Resource Detection** — Automated waste elimination
- **Tagging Strategy** — Cost allocation by team, service, environment

## Lessons Learned

1. **Tagging is the foundation** — without consistent tags, you can't attribute costs to teams
2. **Budget alerts prevent surprises** — set alerts at 80% so you have time to act
3. **Rightsizing is continuous** — usage patterns change; re-analyze quarterly
4. **Spot needs fallback** — always maintain on-demand baseline for critical workloads
5. **Resource quotas need defaults** — limit ranges set sensible defaults for pods that forget to set resources

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
