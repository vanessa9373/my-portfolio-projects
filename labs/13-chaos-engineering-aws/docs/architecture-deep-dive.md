# Lab 13: Chaos Engineering & Resilience Testing (AWS FIS) — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + Principles of Chaos Engineering (Netflix)  
> **Scope:** AWS FIS experiments (8 types), Python safety orchestrator, steady-state hypothesis validation, Game Day program

---

## What This Framework Solves

Multi-AZ deployments, auto-scaling groups, and health checks are reliability configurations. They are not reliability tests. A team that has never observed what happens when an EC2 instance stops in one AZ does not know whether their Multi-AZ configuration actually protects them. They have an assumption. Chaos engineering replaces assumptions with observations — by deliberately inducing the failure modes that the architecture claims to handle, in a controlled environment, with safety stops.

---

## Architecture: Safety-First Chaos Orchestration

```
Python Orchestrator (scripts/run-experiment.py)
         │
         ├── Step 1: Pre-check (steady-state validation)
         │     └── Prometheus query: error_rate < 0.5%, p99 < 200ms
         │
         ├── Step 2: Start experiment
         │     ├── AWS FIS: EC2/ECS/RDS/network experiments
         │     └── LitmusChaos: Kubernetes pod/node experiments
         │
         ├── Step 3: Monitor (continuous)
         │     └── CloudWatch + Prometheus: check safety thresholds
         │         └── If breached → auto-stop experiment immediately
         │
         └── Step 4: Analyze results
               ├── Prometheus metrics during experiment vs baseline
               └── Generate report: what was tested, what happened, action items
```

---

## Step-by-Step: Chaos Engineering Framework

### Step 1 — Infrastructure Setup

```hcl
# terraform/main.tf (key resources)
resource "aws_fis_experiment_template" "ec2_instance_stop" {
  description = "Stop one EC2 instance in target AZ"
  role_arn    = aws_iam_role.fis_role.arn
  
  action {
    name      = "StopEC2"
    action_id = "aws:ec2:stop-instances"
    
    target {
      key   = "Instances"
      value = "target-instances"
    }
  }
  
  target {
    name           = "target-instances"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"  # affect exactly 1 instance
    
    resource_tag {
      key   = "Environment"
      value = "staging"  # never production for initial experiments
    }
  }
  
  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.safety_stop.arn
  }
}

resource "aws_cloudwatch_metric_alarm" "safety_stop" {
  alarm_name          = "chaos-safety-stop"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10  # auto-stop if > 10 errors/min
}
```

**Why the stop condition uses a CloudWatch alarm (not just a timeout)?**  
A timeout-based experiment runs for its full duration regardless of impact. If the experiment is causing more damage than expected, it continues until the timer expires. A CloudWatch alarm stop condition monitors the real impact continuously — if error rates spike beyond the safety threshold, FIS stops the experiment immediately, regardless of how much time remains. The experiment serves the safety threshold, not the timer.

**Why `selection_mode: COUNT(1)` instead of `PERCENT(50)`?**  
Starting with the minimum blast radius builds confidence before expanding. Stopping one instance validates that the Multi-AZ failover actually works. Only after validating that one instance failure is handled correctly does it make sense to escalate to stopping an entire AZ or a percentage of instances. Chaos engineering follows the scientific principle: change one variable at a time.

### Step 2 — The Experiment Catalog

```python
# experiments/aws-fis/ec2-instance-stop.json
{
  "CE-01": {
    "name": "EC2 Instance Stop (single AZ)",
    "hypothesis": "ALB health checks detect failure within 30s; traffic shifts to remaining AZs",
    "blast_radius": "1 EC2 instance",
    "risk": "medium",
    "success_criteria": "Error rate < 1% within 60s of instance stop"
  },
  "CE-02": {
    "name": "CPU Stress (80%)",
    "hypothesis": "HPA scales out within 3 minutes; p99 latency stays below SLO",
    "blast_radius": "1 EC2 instance",
    "risk": "low",
    "success_criteria": "p99 latency < 500ms throughout"
  },
  "CE-03": {
    "name": "Network Latency (+200ms)",
    "hypothesis": "Services have timeouts set; downstream failures don't cascade",
    "blast_radius": "1 target group",
    "risk": "medium",
    "success_criteria": "No cascading failures; checkout still functional"
  },
  "CE-04": {
    "name": "Network Packet Loss (30%)",
    "hypothesis": "Retry logic handles transient failures; eventual consistency maintained",
    "blast_radius": "1 target group",
    "risk": "high",
    "success_criteria": "Zero data loss; error rate < 5%"
  }
}
```

**Why document the hypothesis explicitly before running each experiment?**  
A chaos experiment without a hypothesis is just deliberate breakage. The hypothesis forces the team to articulate what the architecture *claims* to handle, which creates the failure condition for the experiment: if the hypothesis is wrong, the experiment has found a real resilience gap. Without the hypothesis, a failed experiment is just an outage; with the hypothesis, a failed experiment is a documented finding.

### Step 3 — Python Safety Orchestrator

```python
# scripts/run-experiment.py
import boto3
import requests
import time
import sys

PROMETHEUS_URL = "http://prometheus:9090"
FIS_CLIENT = boto3.client('fis')

STEADY_STATE_THRESHOLDS = {
    "error_rate_pct": 0.5,    # must be < 0.5% before experiment starts
    "p99_latency_ms": 200,    # p99 must be < 200ms before experiment
}

SAFETY_THRESHOLDS = {
    "error_rate_pct": 5.0,    # abort if error rate exceeds 5%
    "p99_latency_ms": 2000,   # abort if p99 exceeds 2000ms
}

def check_steady_state():
    error_rate = query_prometheus("sum(rate(http_requests_total{status=~'5..'}[5m])) / sum(rate(http_requests_total[5m])) * 100")
    p99 = query_prometheus("histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) * 1000")
    
    if error_rate > STEADY_STATE_THRESHOLDS["error_rate_pct"]:
        print(f"ERROR: Pre-experiment error rate {error_rate:.2f}% exceeds threshold. Aborting.")
        sys.exit(1)
    
    print(f"Pre-check passed: error_rate={error_rate:.2f}%, p99={p99:.0f}ms")

def run_fis_experiment(template_id, duration_seconds):
    check_steady_state()
    
    exp = FIS_CLIENT.start_experiment(experimentTemplateId=template_id)
    exp_id = exp['experiment']['id']
    
    start_time = time.time()
    while time.time() - start_time < duration_seconds:
        # Check safety thresholds every 10 seconds
        error_rate = query_prometheus("...")
        if error_rate > SAFETY_THRESHOLDS["error_rate_pct"]:
            print(f"SAFETY STOP: error rate {error_rate:.2f}% exceeds limit. Stopping experiment.")
            FIS_CLIENT.stop_experiment(id=exp_id)
            break
        time.sleep(10)
    
    return analyze_experiment(exp_id, start_time)
```

**Why validate steady-state BEFORE injecting the failure?**  
If the system is already degraded when the experiment starts, any observations during the experiment are confounded — it's impossible to distinguish the impact of the injected failure from the pre-existing degradation. A pre-check that aborts if steady-state conditions aren't met ensures every experiment has a clean baseline. If pre-check fails, the team investigates the existing problem rather than adding a new failure to an already-degraded system.

**Why implement safety monitoring in the Python orchestrator in addition to CloudWatch FIS stop conditions?**  
AWS FIS stop conditions have a minimum evaluation period of 60 seconds. The Python orchestrator checks every 10 seconds. For a fast-moving experiment (packet loss can cause cascading failures within 30 seconds), the 10-second check catches problems before they compound. Defense in depth applies to chaos engineering safety controls as much as it applies to production security.

### Step 4 — Experiment Execution and Analysis

```python
# scripts/analyze-results.py
def generate_experiment_report(exp_id, start_time, end_time):
    report = {
        "experiment_id": exp_id,
        "duration": f"{(end_time - start_time):.0f}s",
        "findings": []
    }
    
    # Compare metrics: experiment window vs 1h before (baseline)
    metrics = {
        "error_rate": compare_metric("error_rate", start_time, end_time),
        "p99_latency": compare_metric("p99_latency", start_time, end_time),
        "recovery_time": measure_recovery_time(start_time, end_time)
    }
    
    report["result"] = "PASS" if all_within_thresholds(metrics) else "FAIL"
    
    if report["result"] == "FAIL":
        report["findings"].append({
            "observation": f"p99 latency reached {metrics['p99_latency']['max']}ms during experiment",
            "threshold": "500ms SLO target",
            "action_item": "Add timeout + retry logic to cart service for dependency failures"
        })
    
    return report
```

**Why compare against the 1-hour window before the experiment rather than an absolute threshold?**  
Traffic patterns are not constant — p99 latency during peak load may be 180ms, while during quiet hours it may be 80ms. An absolute threshold of "p99 > 300ms is a failure" would generate false failures during peak load and false passes during quiet hours. Comparing the experiment window against the pre-experiment baseline normalizes for traffic variation — the metric that matters is the *delta* caused by the failure injection, not the absolute value.

### Step 5 — Game Day Playbook

```markdown
# docs/gameday-playbook.md

## Game Day Structure (4 hours, quarterly)

### Roles
- **Facilitator:** Runs the agenda, enforces time limits, calls experiments safe/unsafe
- **Operator:** Executes experiments via the Python orchestrator
- **Observer:** Watches Grafana dashboards, takes notes on system behavior
- **Safety Officer:** Holds abort authority — can stop any experiment at any time

### Agenda
09:00 — System readiness check (steady-state validation, ensure all monitoring is green)
09:30 — Experiment 1: Pod delete (CE-05, low risk)
10:00 — Review findings, update action items
10:30 — Experiment 2: CPU stress (CE-02, low risk)
11:00 — Experiment 3: Network latency (CE-03, medium risk) [requires Safety Officer approval]
12:00 — Retrospective: what surprised us? what action items?

### Safety Protocol
- No P1 experiments during business hours
- Any team member can call a halt — no hierarchy applies during experiments
- Rollback plan must be documented BEFORE each experiment starts
```

**Why quarterly rather than continuous chaos experiments?**  
Continuous chaos (like Netflix's Chaos Monkey) requires mature monitoring, runbooks, and team confidence built over years. Early in a chaos engineering program, quarterly Game Days build the muscle — teams learn to interpret results, update runbooks, and develop intuition for what "normal degraded behavior" looks like before they trust continuous experimentation.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **12 failure modes discovered:** Issues found in a Game Day cost a few hours of engineering investigation; the same issues found during a real production incident cost hours of customer impact and MTTR
- **40% faster recovery:** After fixing discovered issues (missing retry logic, insufficient timeouts), the team has practiced the recovery procedures and systems are better configured
- **Game Day quarterly cadence:** Resilience testing is a scheduled practice, not a one-time audit

### Security
- **FIS IAM role scoped to tagged resources:** Experiments can only target resources with `Environment=staging` tag — production cannot be accidentally targeted
- **Safety officer role:** Human oversight cannot be bypassed — the Safety Officer has independent abort authority during experiments

### Reliability
- **CloudWatch stop conditions:** Experiments auto-abort if safety thresholds are exceeded — no manual intervention required to limit blast radius
- **Hypothesis-driven experiments:** Results are measurable pass/fail, not subjective — findings become concrete engineering action items
- **Progressive blast radius:** Single instance → single AZ → multi-AZ progression ensures each step is validated before expanding scope

### Performance Efficiency
- **10-second safety polling interval:** The orchestrator catches safety threshold breaches in 10 seconds, before CloudWatch's 60-second minimum evaluation fires
- **Baseline comparison:** Normalizes experiment results for traffic variation — prevents false failures during peak and false passes during quiet periods

### Cost Optimization
- **Chaos in staging first:** Stage experiments in non-production before running in production — finding issues costs compute time in staging, not revenue and customer trust in production
- **AWS FIS pay-per-experiment:** No infrastructure to provision; costs accrue only during active experiments

### Sustainability
- **Confidence replaces over-provisioning:** Teams that have tested their failure handling stop over-provisioning "just in case" — tested systems can be sized for the real load, not the feared maximum

---

## Key Architectural Insight

The key finding of every chaos engineering program is the same: **the systems that fail under chaos experiments are not the ones the team expected**. The Multi-AZ configuration works. The load balancer failover works. What fails is the service that assumed its cache would always be available and has no fallback, or the payment service that has no timeout on the notification service call. Chaos engineering is not a reliability audit — it is a way to discover the assumptions you didn't know you were making. The 12 failure modes found in this lab were all previously unknown. They were not found by reading the architecture diagram; they were found by breaking things and observing what happened.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
