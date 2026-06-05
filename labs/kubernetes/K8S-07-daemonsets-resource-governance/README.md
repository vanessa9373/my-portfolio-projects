# K8S-07: DaemonSets & Resource Governance

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![DaemonSet](https://img.shields.io/badge/DaemonSet-Every_Node-blue?style=for-the-badge)
![Resource Governance](https://img.shields.io/badge/ResourceQuota-Governance-orange?style=for-the-badge)
![QoS](https://img.shields.io/badge/QoS-Guaranteed-green?style=for-the-badge)

## Summary (The "Elevator Pitch")

DaemonSets ensure infrastructure agents run on every node in the cluster, while ResourceQuotas, LimitRanges, and PriorityClasses govern how workloads consume and compete for resources. This lab deploys a Fluentd log collector as a DaemonSet, configures namespace-level resource quotas and default limits, demonstrates all three QoS classes, and uses PriorityClasses with PodDisruptionBudgets to control eviction behavior under pressure -- building a complete resource governance framework.

## The Problem

The platform team faces three related resource management failures. First, when new nodes join the cluster (via autoscaling or manual addition), the logging agent is not automatically deployed -- logs from those nodes are silently lost until someone notices and manually deploys the agent. Second, a single team's namespace has no resource boundaries, so a runaway pod consumed 90% of node memory and caused the kubelet to OOM-kill critical system pods. Third, during a node drain for maintenance, all replicas of the payment service were evicted simultaneously, causing a full outage because there was no policy to maintain minimum availability. These are three symptoms of the same root cause: no resource governance framework.

## The Solution

We implement a four-layer resource governance framework. DaemonSets automatically deploy infrastructure agents (logging, monitoring) to every node, including nodes that join after the DaemonSet is created. ResourceQuotas cap the total CPU and memory a namespace can consume, preventing any single team from monopolizing cluster resources. LimitRanges set default requests/limits on pods that do not specify their own, ensuring every pod has a QoS class and predictable resource allocation. PriorityClasses control eviction order under resource pressure (system-critical pods survive while best-effort workloads are evicted first), and PodDisruptionBudgets prevent more than one replica from being evicted during voluntary disruptions like node drains.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                       │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Node 1     │  │   Node 2     │  │   Node 3     │         │
│  │              │  │              │  │              │         │
│  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │         │
│  │  │Fluentd │  │  │  │Fluentd │  │  │  │Fluentd │  │         │
│  │  │(daemon)│  │  │  │(daemon)│  │  │  │(daemon)│  │         │
│  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │         │
│  │              │  │              │  │              │         │
│  │  ┌────────┐  │  │  ┌────────┐  │  │  ┌────────┐  │         │
│  │  │App Pod │  │  │  │App Pod │  │  │  │App Pod │  │         │
│  │  │(QoS:   │  │  │  │(QoS:   │  │  │  │(QoS:   │  │         │
│  │  │Guar.)  │  │  │  │Burst.) │  │  │  │BestEff)│  │         │
│  │  └────────┘  │  │  └────────┘  │  │  └────────┘  │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                 │
│  ┌────────────────── Namespace: team-a ───────────────────────┐ │
│  │                                                             │ │
│  │  ResourceQuota          LimitRange          PDB             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │CPU: 8 cores  │  │Default CPU:  │  │minAvailable: │     │ │
│  │  │Mem: 16Gi     │  │  req: 100m   │  │  2           │     │ │
│  │  │Pods: 20      │  │  lim: 500m   │  │              │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  PriorityClasses:                                               │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ critical-system (1000) > standard (500) > background (100) │ │
│  │ Eviction order: background → standard → critical-system    │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| DaemonSet | Per-node agent deployment | Guarantees exactly one pod per node, auto-deploys to new nodes |
| Fluentd | Log collection agent | Standard Kubernetes log collector, reads container log files |
| ResourceQuota | Namespace resource caps | Prevents any single namespace from consuming all cluster resources |
| LimitRange | Default pod resource settings | Ensures every pod has requests/limits even if not specified |
| PriorityClass | Eviction priority ordering | Controls which pods survive when nodes are under memory pressure |
| PodDisruptionBudget | Voluntary disruption protection | Prevents simultaneous eviction of all replicas during maintenance |
| QoS Classes | Resource guarantee tiers | Kubernetes uses QoS class to determine OOM kill order |

## Implementation Steps

### Step 1: Deploy DaemonSet (Log Collector on Every Node)

```bash
kubectl apply -f manifests/daemonset-logging.yaml

# Verify one pod per node
kubectl get pods -l app=fluentd -o wide
kubectl get daemonset fluentd-logging

# Check that all nodes have the agent
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
READY_COUNT=$(kubectl get daemonset fluentd-logging -o jsonpath='{.status.numberReady}')
echo "Nodes: ${NODE_COUNT}, DaemonSet pods ready: ${READY_COUNT}"
```

**What this does:** Deploys a Fluentd log collection agent as a DaemonSet, ensuring exactly one Fluentd pod runs on every node in the cluster. When new nodes are added (via autoscaling or manual join), the DaemonSet controller automatically schedules a Fluentd pod on them without any manual intervention.

### Step 2: Configure ResourceQuota per Namespace

```bash
kubectl create namespace team-a
kubectl apply -f manifests/resourcequota.yaml -n team-a

# View the quota and current usage
kubectl describe resourcequota team-a-quota -n team-a
```

**What this does:** Sets hard limits on the total CPU (8 cores), memory (16Gi), and pod count (20) that namespace `team-a` can consume. Any pod creation that would exceed these limits is rejected by the admission controller with a clear error message. This prevents a single team from monopolizing shared cluster resources.

### Step 3: Set LimitRange Defaults

```bash
kubectl apply -f manifests/limitrange.yaml -n team-a

# Deploy a pod without resource specifications
kubectl run test-defaults --image=nginx -n team-a
kubectl describe pod test-defaults -n team-a | grep -A5 "Limits\|Requests"
```

**What this does:** Configures default resource requests and limits that are automatically injected into any pod in the namespace that does not specify its own. This ensures every pod has predictable resource allocation and a QoS class, even when developers forget to add resource specifications to their manifests.

### Step 4: Demonstrate QoS Classes

```bash
# Deploy three pods with different resource configurations
kubectl apply -f manifests/qos-guaranteed.yaml -n team-a
kubectl apply -f manifests/qos-burstable.yaml -n team-a
kubectl apply -f manifests/qos-besteffort.yaml -n team-a

# Verify QoS class assignment
for pod in qos-guaranteed qos-burstable qos-besteffort; do
  QOS=$(kubectl get pod ${pod} -n team-a -o jsonpath='{.status.qosClass}')
  echo "${pod}: ${QOS}"
done
```

**What this does:** Creates three pods that demonstrate each Kubernetes QoS class. Guaranteed (requests == limits for all containers), Burstable (requests < limits), and BestEffort (no requests or limits). The kubelet uses QoS class to determine OOM kill order: BestEffort is killed first, then Burstable, then Guaranteed.

### Step 5: Create PriorityClasses

```bash
kubectl apply -f manifests/priority-classes.yaml

# Verify priority classes
kubectl get priorityclasses
```

**What this does:** Defines three PriorityClasses that control pod scheduling priority and eviction order. Higher priority pods can preempt lower priority pods when the cluster is full. Under memory pressure, the kubelet evicts pods in order of lowest priority first, protecting critical system services.

### Step 6: Configure PodDisruptionBudgets

```bash
kubectl apply -f manifests/pdb.yaml -n team-a

# View PDB status
kubectl get pdb -n team-a
kubectl describe pdb myapp-pdb -n team-a
```

**What this does:** Creates a PodDisruptionBudget requiring at least 2 replicas of the application to remain available during voluntary disruptions (node drains, cluster upgrades). The kubectl drain command will respect this budget, evicting at most one pod at a time and waiting for the replacement to be Ready before evicting the next.

### Step 7: Test Eviction Order Under Resource Pressure

```bash
chmod +x scripts/test-eviction.sh
./scripts/test-eviction.sh
```

**What this does:** Simulates resource pressure by deploying memory-hungry pods until the node runs low on memory. Observes the kubelet eviction order -- BestEffort pods are evicted first, then Burstable, while Guaranteed and high-priority pods survive. Validates that PDBs prevent simultaneous eviction of all application replicas.

## Project Structure

```
K8S-07-daemonsets-resource-governance/
├── README.md
├── manifests/
│   ├── daemonset-logging.yaml         # Fluentd DaemonSet for all nodes
│   ├── resourcequota.yaml             # Namespace resource limits
│   ├── limitrange.yaml                # Default pod resource settings
│   ├── priority-classes.yaml          # System/standard/background priorities
│   ├── pdb.yaml                       # PodDisruptionBudget for app
│   ├── qos-guaranteed.yaml            # Pod with requests == limits
│   ├── qos-burstable.yaml            # Pod with requests < limits
│   └── qos-besteffort.yaml           # Pod with no resource specs
└── scripts/
    ├── deploy.sh                      # Deploy all resources
    ├── test-eviction.sh               # Test eviction order
    └── cleanup.sh                     # Remove all resources
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `daemonset-logging.yaml` | Runs Fluentd on every node, mounts /var/log | DaemonSet controller, hostPath volumes, tolerations |
| `resourcequota.yaml` | Caps namespace at 8 CPU, 16Gi mem, 20 pods | Hard limits, admission control, resource accounting |
| `limitrange.yaml` | Injects default 100m CPU / 128Mi mem per container | Default requests/limits, min/max constraints |
| `priority-classes.yaml` | Defines critical (1000), standard (500), background (100) | preemptionPolicy, globalDefault, scheduling priority |
| `pdb.yaml` | Requires minAvailable: 2 for app pods | Voluntary disruption protection, drain safety |
| `qos-guaranteed.yaml` | Pod where requests exactly equal limits | Guaranteed QoS, last to be OOM-killed |
| `qos-burstable.yaml` | Pod with requests lower than limits | Burstable QoS, middle eviction priority |
| `qos-besteffort.yaml` | Pod with no resource specifications | BestEffort QoS, first to be evicted |

## Results & Metrics

| Metric | Before (No Governance) | After (Full Governance) |
|---|---|---|
| Log coverage on new nodes | Manual deploy (hours of lost logs) | Automatic via DaemonSet (zero gap) |
| Namespace resource control | Unbounded (single team consumed 90% node) | Capped at 8 CPU / 16Gi per namespace |
| Pods without resource specs | 40% of pods (BestEffort, unpredictable) | 0% (LimitRange injects defaults) |
| Critical pod eviction | Random (payment service killed) | Protected (highest PriorityClass) |
| Simultaneous replica eviction | All replicas drained at once | PDB enforces minAvailable: 2 |
| OOM kill predictability | Random order | QoS-based: BestEffort first, Guaranteed last |
| Node drain safety | Full outage during maintenance | Rolling eviction with PDB guarantees |

## How I'd Explain This in an Interview

> "We had three resource management problems: logging agents missing from new nodes, no limits on namespace resource consumption, and all replicas getting evicted during maintenance. I built a resource governance framework with four layers. DaemonSets ensure infrastructure agents like Fluentd run on every node automatically -- when a new node joins, the DaemonSet controller deploys the agent without any manual step. ResourceQuotas cap each namespace at a fixed CPU and memory budget so one team can't starve others. LimitRanges inject default resource requests and limits into pods that don't specify their own, guaranteeing every pod gets a QoS class. And PriorityClasses combined with PodDisruptionBudgets control eviction behavior -- critical pods survive resource pressure while best-effort pods are sacrificed first, and PDBs prevent more than one replica from being evicted at a time during node drains."

## Key Concepts Demonstrated

- **DaemonSet** -- Controller that ensures exactly one pod runs on every node (or a subset of nodes matching a selector), automatically deploying to new nodes
- **QoS Classes** -- Kubernetes assigns Guaranteed, Burstable, or BestEffort based on resource specifications, determining OOM kill order
- **ResourceQuota** -- Namespace-level admission controller that enforces hard caps on total CPU, memory, storage, and object counts
- **LimitRange** -- Namespace-level policy that sets default, minimum, and maximum resource values for containers
- **PriorityClass** -- Cluster-scoped object that assigns scheduling priority and preemption behavior to pods
- **PodDisruptionBudget** -- Policy that limits the number of pods from a set that can be simultaneously unavailable during voluntary disruptions
- **Eviction Order** -- Under memory pressure, kubelet evicts BestEffort first, then Burstable exceeding requests, then Guaranteed, respecting PriorityClass within each tier
- **Preemption** -- Higher-priority pods can evict lower-priority pods to get scheduled when no capacity is available

## Lessons Learned

1. **DaemonSet tolerations must match node taints** -- By default, DaemonSet pods are not scheduled on tainted nodes (e.g., master/control-plane nodes). Adding the appropriate tolerations ensures the logging agent covers every node, including control plane nodes that also run workloads.
2. **ResourceQuotas require all pods to have requests** -- Once a ResourceQuota is applied to a namespace, pods without resource requests are rejected. Always pair ResourceQuotas with LimitRanges to inject defaults, or teams will get cryptic admission errors.
3. **PDB minAvailable vs maxUnavailable matters for small replica counts** -- With 3 replicas and `minAvailable: 2`, only 1 pod can be disrupted. With `maxUnavailable: 1`, the same behavior. But with 3 replicas and `minAvailable: 3`, node drains are blocked entirely -- choose carefully.
4. **QoS Guaranteed requires exact equality** -- For Guaranteed QoS, every container in the pod must have requests equal to limits for both CPU and memory. Missing a limit on even one container drops the pod to Burstable, changing eviction behavior.
5. **PriorityClass preemption can cause cascading evictions** -- Setting a very high priority on a Deployment with many replicas can cause it to evict dozens of lower-priority pods during scale-up. Use `preemptionPolicy: Never` on PriorityClasses that need priority for eviction ordering but should not preempt others.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
