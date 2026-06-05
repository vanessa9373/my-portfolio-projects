# Phase 13: FinOps & Cost Optimization

**Difficulty:** Expert | **Time:** 5-7 hours | **Prerequisites:** Phase 12

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

FinOps brings financial accountability to cloud spending. This phase implements automated cost optimization through intelligent node provisioning and comprehensive cost visibility, achieving a 40% reduction in infrastructure costs.

### Cost Optimization Strategy

```
┌──────────────────────────────────────────────────────────────┐
│                    FinOps Framework                           │
│                                                              │
│  1. Inform — Cost visibility and allocation                  │
│     └── Kubecost: per-service, per-team cost breakdown       │
│                                                              │
│  2. Optimize — Reduce waste                                  │
│     └── Karpenter: Spot instances, right-sizing,             │
│         consolidation                                        │
│                                                              │
│  3. Operate — Continuous governance                          │
│     └── Budget alerts, resource quotas, anomaly detection    │
└──────────────────────────────────────────────────────────────┘
```

### Key Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Monthly compute cost | $25,000 | $15,000 | 40% reduction |
| Spot instance usage | 0% | 70% | — |
| Resource utilization | ~30% | ~65% | 2x improvement |
| Idle resource waste | ~$4,000/mo | ~$500/mo | 87% reduction |
| Cost allocation coverage | 0% | 100% | Full visibility |

### Directory Structure

```
phase-13-finops/
├── karpenter/
│   └── provisioner.yaml           # Node provisioning with Spot preference
└── kubecost/
    └── cost-allocation.yaml       # Cost model, alerts, quotas, limits
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Helm | 3.13+ | Installed in Phase 6 |
| kubectl | 1.28+ | Installed in Phase 4 |
| AWS CLI | 2.x | Installed in Phase 4 |

### Install Karpenter

```bash
# Set environment variables
export CLUSTER_NAME=ecommerce-production
export KARPENTER_VERSION=v0.33.0

# Install Karpenter
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version $KARPENTER_VERSION \
  --namespace karpenter \
  --create-namespace \
  --set settings.clusterName=$CLUSTER_NAME \
  --set settings.clusterEndpoint=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.endpoint" --output text) \
  --wait
```

### Install Kubecost

```bash
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="<YOUR_TOKEN>"
```

---

## 3. Step-by-Step Implementation

### Step 1: Deploy Karpenter Provisioner

Apply the Karpenter provisioner configuration:

```bash
kubectl apply -f karpenter/provisioner.yaml
```

Verify Karpenter is managing nodes:

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Check provisioner status
kubectl get provisioner default -o yaml

# Watch node provisioning
kubectl get nodes -w
```

### Step 2: Migrate from Managed Node Groups to Karpenter

```bash
# Cordon managed node group nodes (no new pods scheduled)
kubectl cordon -l eks.amazonaws.com/nodegroup=ecommerce-production-ng

# Drain nodes one at a time (Karpenter provisions replacements)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Karpenter will automatically provision optimal nodes for the pending pods
# Watch the process:
kubectl get nodes -w
kubectl get pods -n production -o wide
```

### Step 3: Deploy Kubecost Cost Allocation

Apply the cost allocation configuration:

```bash
kubectl apply -f kubecost/cost-allocation.yaml
```

Access the Kubecost dashboard:

```bash
kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090
# Open http://localhost:9090
```

### Step 4: Configure Resource Quotas

The cost allocation YAML includes ResourceQuota and LimitRange resources that enforce cost guardrails at the namespace level:

```bash
# Verify quotas are applied
kubectl get resourcequota -n production
kubectl describe resourcequota production-quota -n production

# Verify limit ranges
kubectl get limitrange -n production
kubectl describe limitrange production-limits -n production
```

### Step 5: Set Up Cost Alerts

Verify Kubecost alerts are configured:

```bash
# Check Kubecost alert policy
kubectl get configmap kubecost-alert-configs -n kubecost -o yaml

# Test Slack notification (adjust webhook URL in configuration)
# Alerts trigger when:
# - Namespace cost spikes > 20% over 7-day baseline
# - Unallocated costs > 15% of total
# - Monthly budget exceeds $15,000
# - Resource efficiency drops below 40%
```

### Step 6: Verify Cost Savings

```bash
# Check Spot instance distribution
kubectl get nodes -o custom-columns=\
  NAME:.metadata.name,\
  INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,\
  CAPACITY:.metadata.labels.karpenter\\.sh/capacity-type

# Expected: ~70% Spot, ~30% On-Demand

# Check Kubecost savings report
# Dashboard → Savings → Right-sizing recommendations
```

---

## 4. Configuration Walkthrough

### `karpenter/provisioner.yaml` — Section by Section

#### Provisioner (Node Selection Strategy)

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    # Capacity type preference: try Spot first, fall back to On-Demand
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
      # Spot instances are 60-90% cheaper than On-Demand
      # Karpenter automatically handles Spot interruptions

    # Instance type flexibility
    - key: node.kubernetes.io/instance-type
      operator: In
      values:
        - m5.large          # 2 vCPU, 8 GB — $0.096/hr On-Demand
        - m5.xlarge         # 4 vCPU, 16 GB — $0.192/hr On-Demand
        - m5a.large         # 2 vCPU, 8 GB — AMD, cheaper
        - m5a.xlarge        # 4 vCPU, 16 GB — AMD, cheaper
        - m6i.large         # 2 vCPU, 8 GB — latest gen
        - m6i.xlarge        # 4 vCPU, 16 GB — latest gen
      # Multiple families increase Spot availability
      # AWS picks the cheapest available instance

    # Spread across all 3 AZs
    - key: topology.kubernetes.io/zone
      operator: In
      values: ["us-east-1a", "us-east-1b", "us-east-1c"]

  limits:
    resources:
      cpu: "100"           # Maximum 100 CPU cores across all Karpenter nodes
      memory: 400Gi        # Maximum 400 GB RAM across all Karpenter nodes
      # Prevents runaway scaling (cost ceiling)

  consolidation:
    enabled: true          # Automatically bin-pack pods onto fewer nodes
                            # Replaces underutilized nodes with right-sized ones

  ttlSecondsAfterEmpty: 30     # Delete empty nodes after 30 seconds
                                # Prevents paying for idle capacity

  ttlSecondsUntilExpired: 2592000  # Force node rotation every 30 days
                                     # Ensures nodes get latest security patches
```

#### AWSNodeTemplate (Node Configuration)

```yaml
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  amiFamily: Bottlerocket         # Security-focused container OS (from Phase 4)

  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi          # 50 GB root volume
        volumeType: gp3           # Latest gen EBS (3000 IOPS baseline, free)
        encrypted: true           # EBS encryption at rest

  subnetSelector:
    karpenter.sh/discovery: ecommerce-production
    # Automatically discovers private subnets tagged for Karpenter

  securityGroupSelector:
    karpenter.sh/discovery: ecommerce-production
    # Automatically discovers security groups tagged for Karpenter
```

### `kubecost/cost-allocation.yaml` — Key Sections

#### CostModel Configuration

```yaml
# Shared namespace costs are distributed across teams
sharedNamespaces:
  - kube-system          # Kubernetes system components
  - istio-system         # Service mesh
  - monitoring           # Prometheus, Grafana, Loki
  - cert-manager         # TLS certificates
  - argocd               # GitOps
  - gatekeeper-system    # Admission control

# Fixed infrastructure costs allocated proportionally
sharedOverheadCosts:
  controlPlane: 73       # EKS control plane: $73/month
  loadBalancers: 120     # ALB: ~$120/month
  natGateways: 200       # 3 NAT Gateways: ~$200/month

# Cost aggregation by labels — enables per-team and per-service reporting
aggregation:
  - team                  # Cost by team (label: team=platform)
  - service               # Cost by service (label: app=user-service)
  - environment           # Cost by environment (label: env=production)
```

#### Alert Policies

```yaml
# Alert 1: Cost spike — 20% increase over baseline
- type: budget
  threshold: 0.20                # 20% over 7-day average
  window: 7d                     # Compare to last 7 days
  aggregation: namespace
  # Example: If user-service usually costs $100/day and spikes to $120+

# Alert 2: Unallocated costs too high
- type: efficiency
  threshold: 0.15                # More than 15% unallocated
  # Unallocated costs = resources not attributable to a specific workload

# Alert 3: Monthly budget overrun
- type: budget
  threshold: 15000               # $15,000 USD monthly budget
  window: monthly

# Alert 4: Low resource efficiency
- type: efficiency
  threshold: 0.40                # Below 40% utilization
  # Requests vs. actual usage — indicates over-provisioned pods
```

#### ResourceQuota (Namespace Limits)

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "40"           # 40 CPU cores total for all pods
    limits.cpu: "80"             # 80 CPU cores limit
    requests.memory: 80Gi       # 80 GB memory requests
    limits.memory: 160Gi        # 160 GB memory limit
    requests.storage: 500Gi     # 500 GB persistent storage
    persistentvolumeclaims: "50" # Max 50 PVCs
    pods: "200"                  # Max 200 pods in namespace
    services: "30"               # Max 30 services
```

#### LimitRange (Per-Container Defaults)

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:                    # Applied if pod doesn't specify limits
        cpu: 500m
        memory: 512Mi
      defaultRequest:             # Applied if pod doesn't specify requests
        cpu: 100m
        memory: 128Mi
      min:                        # No container can request less than this
        cpu: 10m
        memory: 16Mi
      max:                        # No container can request more than this
        cpu: "8"
        memory: 16Gi
    - type: Pod
      max:                        # No pod (all containers combined) can exceed this
        cpu: "16"
        memory: 32Gi
```

---

## 5. Verification Checklist

- [ ] Karpenter is running: `kubectl get pods -n karpenter`
- [ ] Provisioner created: `kubectl get provisioner default`
- [ ] Nodes are being provisioned by Karpenter: `kubectl get nodes -l karpenter.sh/provisioner-name=default`
- [ ] Spot instances are being used: check `karpenter.sh/capacity-type` label on nodes
- [ ] Node consolidation working: Karpenter replaces underutilized nodes
- [ ] Kubecost dashboard accessible and showing cost data
- [ ] Cost allocation shows per-service breakdown
- [ ] Alert policies configured: check Kubecost settings
- [ ] ResourceQuota enforced: `kubectl describe resourcequota -n production`
- [ ] LimitRange defaults applied: deploy a pod without resource specs, verify defaults
- [ ] Spot to On-Demand ratio is approximately 70/30
- [ ] Monthly cost trending toward 40% reduction target

---

## 6. Troubleshooting

### Karpenter not provisioning nodes

```bash
# Check Karpenter controller logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Common causes:
# 1. No pending pods (nothing to schedule)
# 2. Instance type not available in the AZ
# 3. Subnet/security group selector not matching any resources
# 4. Cluster limits reached (cpu: 100, memory: 400Gi)
```

### Spot instance interrupted

```bash
# Karpenter handles Spot interruptions automatically:
# 1. AWS sends a 2-minute warning
# 2. Karpenter cordons and drains the node
# 3. Pods are rescheduled to other nodes
# 4. New node provisioned if needed

# Check interruption events
kubectl get events --field-selector reason=SpotInterrupted
```

### ResourceQuota preventing deployments

```bash
# Check current quota usage
kubectl describe resourcequota production-quota -n production

# If at capacity:
# 1. Scale down other deployments
# 2. Right-size container resources (reduce requests)
# 3. Increase the quota (after approval)
```

### Kubecost showing inaccurate costs

```bash
# Kubecost needs 48 hours of data for accurate cost allocation
# Check data ingestion status
kubectl logs -n kubecost -l app=cost-analyzer

# Verify cloud integration
# Kubecost UI → Settings → Cloud Integration → AWS
```

### Consolidation too aggressive

```bash
# If Karpenter is disrupting pods too frequently:
# 1. Add PDB to critical services (already done in Phase 6)
# 2. Increase ttlSecondsAfterEmpty
# 3. Use do-not-disrupt annotation:
kubectl annotate node <node-name> karpenter.sh/do-not-disrupt=true
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Karpenter vs. Cluster Autoscaler** | Karpenter | Cluster Autoscaler | Faster provisioning (~30s vs ~2-3 min), better bin-packing, Spot integration. Trade-off: AWS-specific. |
| **Spot-first strategy** | Spot preferred | On-Demand only | 60-90% cost savings. Trade-off: 2-minute interruption risk (mitigated by PDB and multiple instance types). |
| **Multiple instance families** | m5, m5a, m6i | Single family | Higher Spot availability, lower prices. Trade-off: slightly inconsistent performance across families. |
| **Consolidation** | Enabled | Disabled | Automatic right-sizing saves money. Trade-off: pod disruptions during consolidation (mitigated by PDB). |
| **Kubecost vs. AWS Cost Explorer** | Kubecost | AWS Cost Explorer | Kubernetes-native, per-pod granularity. Trade-off: additional tool to manage. |

---

## 8. Production Considerations

- **Savings Plans** — Purchase Compute Savings Plans for the On-Demand baseline (30% remaining after Spot)
- **Reserved capacity** — For database nodes (RDS, ElastiCache), use Reserved Instances for 1-3 year terms
- **Tagging enforcement** — Require cost allocation tags on all resources; reject untagged resources via SCP
- **Monthly reviews** — Hold monthly FinOps reviews to analyze cost trends, optimization opportunities, and budget adherence
- **Team chargebacks** — Use Kubecost's team-level cost allocation to charge costs back to owning teams
- **Graviton instances** — Consider `m6g` (ARM-based) instances for additional 20% savings where application supports it
- **Right-sizing cadence** — Review Kubecost right-sizing recommendations weekly and apply during maintenance windows

---

## 9. Next Phase

**[Phase 14: Platform Engineering & Developer Portal →](../phase-14-platform-engineering/README.md)**

With costs optimized, Phase 14 completes the DevOps journey by building an internal developer platform — Backstage for service cataloging and golden path templates, Crossplane for self-service infrastructure, enabling developers to spin up new services in 5 minutes.

---

[← Phase 12: Multi-Region](../phase-12-multi-region/README.md) | [Back to Project Overview](../README.md) | [Phase 14: Platform Engineering →](../phase-14-platform-engineering/README.md)
