# Phase 10: Chaos Engineering & Resilience

**Difficulty:** Advanced | **Time:** 5-7 hours | **Prerequisites:** Phase 9

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

Chaos engineering proactively tests system resilience by injecting controlled failures. Instead of waiting for production incidents, you simulate them in a safe environment and verify that the platform recovers gracefully.

### Chaos Engineering Principles

1. **Start with a hypothesis** — "If 50% of order-service pods are killed, the API Gateway health check should still pass"
2. **Minimize blast radius** — Start small (one pod), expand gradually (entire AZ)
3. **Run in production** — After validating in staging, run in production during low-traffic windows
4. **Automate** — Integrate chaos tests into CI/CD and monthly game days

### Experiment Types

```
┌──────────────────────────────────────────────────────────────┐
│                     Chaos Experiments                         │
│                                                              │
│  Application Layer (Litmus Chaos)                           │
│  ├── Pod kill — Delete random pods                           │
│  ├── Pod network latency — Inject 500ms delay                │
│  ├── CPU stress — Consume CPU on target pods                 │
│  └── Memory stress — Consume memory on target pods           │
│                                                              │
│  Infrastructure Layer (AWS FIS)                              │
│  ├── AZ failure — Stop all instances in one AZ               │
│  ├── Network disruption — Block traffic between AZs          │
│  ├── RDS failover — Trigger Aurora failover                  │
│  └── EC2 instance stop — Kill specific nodes                 │
└──────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
phase-10-chaos/
├── litmus/
│   └── pod-kill.yaml              # Litmus ChaosEngine for pod deletion
└── aws-fis/
    └── az-failure-experiment.json  # AWS FIS AZ failure template
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Litmus CLI | 3.x | `brew install litmuschaos/tap/litmusctl` |
| AWS CLI | 2.x | Installed in Phase 4 |
| kubectl | 1.28+ | Installed in Phase 4 |

### Install Litmus Chaos

```bash
# Install Litmus ChaosCenter
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm
helm install litmus litmuschaos/litmus \
  --namespace litmus \
  --create-namespace

# Install ChaosHub experiments
kubectl apply -f https://hub.litmuschaos.io/api/chaos/3.0.0?file=charts/generic/experiments.yaml -n litmus

# Create a service account for chaos experiments
kubectl create serviceaccount litmus-admin -n production
kubectl create clusterrolebinding litmus-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=production:litmus-admin
```

---

## 3. Step-by-Step Implementation

### Step 1: Define the Hypothesis

Before running any experiment, document your hypothesis:

```
Experiment: Pod Kill — Order Service
Hypothesis: Killing 50% of order-service pods should NOT cause API Gateway
            health check failures. Kubernetes should reschedule pods within
            30 seconds, and the PDB ensures at least 2 pods remain running.

Steady State:
  - API Gateway /health returns 200
  - Order Service has 3/3 running pods
  - P99 latency < 500ms

Expected Behavior:
  - Killed pods are rescheduled within 30 seconds
  - Remaining pods absorb traffic (HPA may scale up)
  - No 5xx errors during the experiment
  - Error budget consumption < 0.01%
```

### Step 2: Run the Pod Kill Experiment (Litmus)

Apply the ChaosEngine:

```bash
kubectl apply -f litmus/pod-kill.yaml
```

Monitor the experiment:

```bash
# Watch chaos engine status
kubectl get chaosengine order-service-chaos -n production -w

# Watch pods being killed and recreated
kubectl get pods -n production -l app=order-service -w

# Check the HTTP probe result
kubectl get chaosresult order-service-chaos-pod-delete -n production -o yaml
```

**Expected output during experiment:**

```
NAME                              READY   STATUS        RESTARTS   AGE
order-service-6d5b8c9f4-abc12    2/2     Running       0          5m
order-service-6d5b8c9f4-def34    2/2     Terminating   0          5m    ← Killed
order-service-6d5b8c9f4-ghi56    2/2     Running       0          5m
order-service-6d5b8c9f4-jkl78    0/2     Pending       0          2s     ← Rescheduled
```

### Step 3: Run the AZ Failure Experiment (AWS FIS)

Create the experiment from the template:

```bash
aws fis create-experiment-template \
  --cli-input-json file://aws-fis/az-failure-experiment.json
```

Start the experiment:

```bash
aws fis start-experiment \
  --experiment-template-id EXT_TEMPLATE_ID

# Monitor the experiment
aws fis get-experiment --id EXP_ID \
  --query 'experiment.state.status'
```

Monitor the impact:

```bash
# Watch node status — nodes in the affected AZ should become NotReady
kubectl get nodes -w

# Verify pods are rescheduled to other AZs
kubectl get pods -n production -o wide

# Check the API Gateway health
curl -sf https://api.ecommerce.com/health
```

### Step 4: Validate the Results

```bash
# Check ChaosResult
kubectl get chaosresult -n production

# Expected: verdict = "Pass"
# The HTTP probe should confirm API Gateway remained healthy throughout

# Check error budget impact
# Query Prometheus:
# slo:error_budget:remaining (should still be > 0.99)
```

### Step 5: Document the Results

```markdown
## Experiment Results: Pod Kill — Order Service

| Metric | Expected | Actual | Status |
|--------|----------|--------|--------|
| API Gateway health | 200 throughout | 200 throughout | PASS |
| Pod rescheduling time | < 30s | 12s | PASS |
| 5xx errors | 0 | 0 | PASS |
| P99 latency | < 500ms | 380ms | PASS |
| Error budget consumed | < 0.01% | 0.002% | PASS |

**Verdict: PASS** — The platform correctly handles 50% pod loss in the Order Service.
```

---

## 4. Configuration Walkthrough

### `litmus/pod-kill.yaml` — Line by Line

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: order-service-chaos
  namespace: production
spec:
  appinfo:
    appns: production                     # Target namespace
    applabel: app=order-service           # Target pods by label
    appkind: deployment                   # Target resource type
  engineState: active                     # Start the experiment immediately
  chaosServiceAccount: litmus-admin       # Service account with permissions to kill pods
  monitoring: true                        # Enable Prometheus metrics for the experiment
  jobCleanUpPolicy: retain                # Keep experiment pods for debugging
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "30"                 # Run for 30 seconds total
            - name: CHAOS_INTERVAL
              value: "10"                 # Kill pods every 10 seconds
            - name: FORCE
              value: "false"              # Graceful deletion (SIGTERM, not SIGKILL)
            - name: PODS_AFFECTED_PERC
              value: "50"                 # Kill 50% of matching pods
        probe:
          - name: check-api-availability
            type: httpProbe               # HTTP health check probe
            httpProbe/inputs:
              url: http://api-gateway.production.svc:3000/health
              method:
                get:
                  criteria: ==
                  responseCode: "200"     # Expect HTTP 200
            mode: Continuous              # Check throughout the experiment
            runProperties:
              probeTimeout: 5             # Timeout per probe
              interval: 5                 # Check every 5 seconds
              retry: 3                    # Retry 3 times before marking probe failed
```

### `aws-fis/az-failure-experiment.json` — Key Sections

```json
{
  "description": "Simulate AZ failure in us-east-1a",
  "actions": {
    "stop-instances": {
      "actionId": "aws:ec2:stop-instances",
      "parameters": { "startInstancesAfterDuration": "PT10M" },
      // Stop EC2 instances for 10 minutes, then restart automatically
      "targets": { "Instances": "az-1a-instances" }
    },
    "network-disruption": {
      "actionId": "aws:ec2:send-spot-instance-interruptions",
      "targets": { "SpotInstances": "az-1a-spot" }
    },
    "inject-latency": {
      "actionId": "aws:ssm:send-command",
      "parameters": {
        "documentArn": "...",
        // Inject 5000ms latency with 500ms jitter
        // Simulates degraded network in the affected AZ
      }
    },
    "inject-packet-loss": {
      "actionId": "aws:ssm:send-command",
      "parameters": {
        // 80% packet loss — near-total AZ isolation
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:...:alarm:high-error-rate"
      // Automatically stop the experiment if errors exceed the threshold
      // This is the safety net — prevents customer impact
    },
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:...:alarm:revenue-impact"
    }
  ]
}
```

Stop conditions are critical — they automatically abort the experiment if real customer impact is detected.

---

## 5. Verification Checklist

- [ ] Litmus Chaos is installed: `kubectl get pods -n litmus`
- [ ] ChaosHub experiments available: `kubectl get chaosexperiments -n litmus`
- [ ] Pod kill experiment completes: `kubectl get chaosengine order-service-chaos -n production`
- [ ] ChaosResult verdict is "Pass": `kubectl get chaosresult -n production -o yaml`
- [ ] HTTP probe passed continuously during the experiment
- [ ] Killed pods rescheduled within 30 seconds
- [ ] No 5xx errors during the experiment (check Prometheus)
- [ ] AWS FIS experiment template created: `aws fis list-experiment-templates`
- [ ] Stop conditions properly abort experiments when thresholds are breached
- [ ] Game day runbook documented with hypotheses and results

---

## 6. Troubleshooting

### ChaosEngine stuck in "initialized" state

```bash
# Check litmus operator logs
kubectl logs -n litmus -l app=chaos-operator

# Verify the service account has permissions
kubectl auth can-i delete pods --as=system:serviceaccount:production:litmus-admin -n production
```

### Pod kill experiment shows "Fail" verdict

```bash
# Check the probe results
kubectl get chaosresult order-service-chaos-pod-delete -n production -o yaml

# If the HTTP probe failed, check:
# 1. Is the API Gateway URL correct?
# 2. Is DNS resolution working within the experiment pod?
# 3. Are there network policies blocking the probe?
```

### AWS FIS experiment aborted by stop condition

```bash
# This is expected behavior if real impact was detected
# Check which alarm triggered:
aws fis get-experiment --id EXP_ID --query 'experiment.state'

# Review the CloudWatch alarm that triggered
aws cloudwatch describe-alarms --alarm-names high-error-rate
```

### Pods not rescheduling after kill

```bash
# Check if the cluster has capacity
kubectl top nodes

# Check if PDB is blocking the rescheduling
kubectl get pdb -n production

# Check pending pods
kubectl get pods -n production --field-selector=status.phase=Pending
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Litmus vs. Chaos Mesh** | Litmus Chaos | Chaos Mesh / Gremlin | CNCF project, rich experiment library, Kubernetes-native. Trade-off: Gremlin has better enterprise UI. |
| **AWS FIS vs. custom scripts** | AWS FIS | Custom boto3 scripts | Managed service with safety controls, CloudWatch integration. Trade-off: AWS-only. |
| **Graceful vs. forced kill** | Graceful (`FORCE=false`) | Force kill (`SIGKILL`) | Tests normal shutdown behavior. Trade-off: doesn't test crash recovery. Run both. |
| **50% pod kill** | 50% | 100% (kill all) | Tests degraded mode, not total outage. Trade-off: doesn't validate recovery from zero replicas. |
| **Stop conditions** | Enabled | None | Safety net prevents customer impact. Trade-off: may abort experiment before seeing full failure mode. |

---

## 8. Production Considerations

- **Game days** — Schedule monthly chaos game days with the full team; rotate the "game master" role
- **Graduated complexity** — Start with pod kills → network latency → AZ failures → multi-region
- **Business hours** — Run chaos experiments during low-traffic windows with the team present
- **Incident correlation** — Tag chaos experiments in observability tools so alerts are not confused with real incidents
- **Resilience4j patterns** — Validate circuit breakers, retries, and bulkheads with chaos experiments
- **Regression suite** — Add passing chaos experiments to the CI/CD pipeline as resilience regression tests
- **Blast radius control** — Always start with the smallest blast radius and expand; never start with full AZ failure

---

## 9. Next Phase

**[Phase 11: Service Mesh & Advanced Networking →](../phase-11-service-mesh/README.md)**

With resilience validated through chaos experiments, Phase 11 adds Istio service mesh for mTLS encryption, canary deployments with automated rollback, circuit breaking, and traffic management — all without changing application code.

---

[← Phase 9: Security](../phase-09-security/README.md) | [Back to Project Overview](../README.md) | [Phase 11: Service Mesh →](../phase-11-service-mesh/README.md)
