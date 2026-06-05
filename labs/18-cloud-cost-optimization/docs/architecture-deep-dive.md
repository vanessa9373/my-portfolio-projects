# Lab 18: Cloud Cost Optimization (FinOps) — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + FinOps Foundation Framework  
> **Scope:** 4-pillar FinOps — visibility (Cost Explorer + CUR), governance (budget alerts), rightsizing (Lambda analyzer), optimization (spot instances + Kubernetes resource controls)

---

## What This Framework Solves

Cloud cost growth is predictable: teams over-provision to avoid reliability incidents, idle resources accumulate because cleanup is lower priority than feature work, nobody uses Reserved Instances because capacity planning is uncertain, and the monthly bill is a surprise because there are no alerts until it arrives. The FinOps framework addresses each of these failure modes systematically: visibility makes the problem legible, governance creates accountability, rightsizing analysis provides data-driven optimization targets, and spot instances reduce the cost of variable workloads without manual capacity management.

---

## Architecture: Four-Pillar FinOps Stack

```
Pillar 1: VISIBILITY
  AWS Cost Explorer → per-service, per-team, per-environment cost breakdown
  Cost and Usage Reports (CUR) → S3 → Athena → detailed line-item analysis
  Anomaly Detection → ML-based alerts when spending deviates from baseline

Pillar 2: GOVERNANCE
  AWS Budgets → per-team budgets with alerts at 80% / 90% / 100%
  SNS → Slack + Email notification
  Resource tagging strategy → cost-center, team, environment tags mandatory

Pillar 3: RIGHTSIZING
  Lambda Analyzer (weekly) → reads CloudWatch metrics → identifies over-provisioned instances
  Recommendation report → Slack + email → engineering team action items

Pillar 4: OPTIMIZATION
  Mixed-instance ASG → on-demand baseline + spot burst (60-90% spot savings)
  Kubernetes ResourceQuota → per-namespace CPU/memory spending caps
  Kubernetes LimitRange → default pod resource requests (no unbounded pods)
  Idle resource detector → finds unused EBS, EIPs, load balancers
```

---

## Step-by-Step: FinOps Framework

### Step 1 — Cost Visibility Infrastructure

```hcl
# terraform/cost-monitoring/main.tf
resource "aws_cur_report_definition" "main" {
  report_name                = "detailed-cost-report"
  time_unit                  = "DAILY"
  format                     = "Parquet"  # columnar format, 10× smaller than CSV
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]  # line-item resource IDs
  
  s3_bucket = aws_s3_bucket.cur_reports.bucket
  s3_prefix = "cost-reports"
  s3_region  = "us-east-1"
  
  additional_artifacts = ["ATHENA"]  # auto-generates Athena table configuration
  
  refresh_closed_reports = true
}

resource "aws_ce_anomaly_monitor" "main" {
  name         = "cost-anomaly-monitor"
  monitor_type = "DIMENSIONAL"
  
  monitor_dimension = "SERVICE"  # monitor per-service anomalies
}

resource "aws_ce_anomaly_subscription" "main" {
  name      = "cost-anomaly-alert"
  threshold = 20  # alert if actual cost exceeds expected by $20
  
  monitor_arn_list = [aws_ce_anomaly_monitor.main.arn]
  
  subscriber {
    address = aws_sns_topic.cost_alerts.arn
    type    = "SNS"
  }
}
```

**Why Parquet format for CUR reports rather than CSV?**  
CSV cost reports for a 50-service application can be gigabytes per month. Athena charges $5 per terabyte scanned. Parquet is a columnar format with compression — the same CUR data is 5-10× smaller in Parquet than CSV. When Athena queries a Parquet file for specific columns (e.g., `SELECT service, cost WHERE month='2026-06'`), it reads only those columns, not the entire file. A query that costs $5 on CSV costs $0.50 on Parquet.

**Why `additional_schema_elements: RESOURCES`?**  
Without `RESOURCES`, the CUR shows costs at the service level (EC2: $3,200/month). With `RESOURCES`, it shows costs at the resource level (instance i-0abc123: $45/month). This is necessary for identifying specific over-provisioned instances, not just over-expensive services. Rightsizing requires resource-level data; service-level aggregation cannot identify which specific EC2 instance to downsize.

**Why ML-based anomaly detection rather than a fixed spending threshold alert?**  
A fixed alert ($5,000/month) fires when you exceed the threshold — but it cannot tell you whether this is expected growth (new service launched) or unexpected growth (runaway Lambda function). ML-based anomaly detection learns the baseline pattern for each service and alerts when actual spending deviates beyond the expected range. A 30% spike in EC2 spending is only suspicious if it wasn't preceded by a deployment of 10 new services.

### Step 2 — Budget Governance

```hcl
# terraform/budget-alerts/main.tf
resource "aws_budgets_budget" "per_team" {
  for_each = var.team_budgets  # map of team name → monthly limit
  
  name         = "team-${each.key}-monthly"
  budget_type  = "COST"
  limit_amount = each.value
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:team$${each.key}"]  # requires "team" tag on all resources
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "FORECASTED"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
}
```

**Why both `ACTUAL` 80% and `FORECASTED` 100% thresholds?**  
The 80% actual alert fires when you've spent 80% of the budget — there's still 20% remaining to investigate and course-correct. The 100% forecasted alert fires when AWS projects that you *will* exceed the budget before the month ends, based on current spending rate. The forecasted alert can fire as early as the 15th of the month if spending is running 2× the budget rate — giving two weeks to take action. Waiting for 100% actual means the budget is already blown before you're notified.

**Why filter budgets by tag value (`user:team$${team_name}`)?**  
An untagged budget tracks total account spending. A tagged budget tracks only resources with the matching tag. This enables per-team accountability: the platform team is responsible only for platform resources (tagged `team=platform`), not for the application team's EC2 instances. Without tagging, cost attribution requires manual analysis; with tagging, it's automatic.

**Why is tagging non-negotiable for FinOps?**  
Without consistent tagging, it is impossible to answer "how much does the checkout service cost?" The answer is embedded in aggregate EC2, RDS, Lambda, and data transfer line items that aren't service-attributed. Tagging (`service=checkout, environment=production, team=payments`) makes cost attribution mechanical. A tagging compliance rule in AWS Config can flag untagged resources immediately upon creation — before they accumulate unreachable costs.

### Step 3 — Rightsizing Lambda Analyzer

```python
# terraform/rightsizing/lambda/index.py
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
ec2 = boto3.client('ec2')

def handler(event, context):
    # Get all running EC2 instances
    instances = ec2.describe_instances(
        Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
    )
    
    recommendations = []
    
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            instance_type = instance['InstanceType']
            
            # Get average CPU over 14 days
            cpu_avg = get_metric_average(
                instance_id, 'AWS/EC2', 'CPUUtilization', 14
            )
            
            # Rightsizing criteria: consistently < 10% CPU utilization
            if cpu_avg < 10:
                next_size = get_smaller_instance_type(instance_type)
                savings = estimate_monthly_savings(instance_type, next_size)
                
                recommendations.append({
                    'instance_id': instance_id,
                    'current_type': instance_type,
                    'avg_cpu_14d': f"{cpu_avg:.1f}%",
                    'recommended_type': next_size,
                    'estimated_monthly_savings': f"${savings:.0f}",
                    'confidence': 'HIGH' if cpu_avg < 5 else 'MEDIUM'
                })
    
    post_recommendations_to_slack(recommendations)
    return {'recommendations_count': len(recommendations)}

def get_metric_average(resource_id, namespace, metric, days):
    response = cloudwatch.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric,
        Dimensions=[{'Name': 'InstanceId', 'Value': resource_id}],
        StartTime=datetime.now() - timedelta(days=days),
        EndTime=datetime.now(),
        Period=86400,  # daily average
        Statistics=['Average']
    )
    datapoints = response['Datapoints']
    return sum(d['Average'] for d in datapoints) / len(datapoints) if datapoints else 0
```

**Why a 14-day average for rightsizing decisions rather than a 1-day snapshot?**  
A 1-day CPU snapshot may capture an unusually quiet day (weekend, holiday) or an unusually busy day (end-of-quarter reporting). A 14-day average captures two full weekly business cycles, including at least two weekends and two weeks of normal business load. This smooths out pattern variation and produces recommendations that reflect actual steady-state utilization rather than a single point in time.

**Why `< 10% average CPU` as the rightsizing threshold?**  
An instance at 10% average CPU utilization is using 10% of its purchased capacity. If the instance has peaks to 30% (3× average), there's still a comfortable margin to the typical 70% HPA target. An instance at 50% average CPU is much closer to the point where a downsize would push it into throttling. The 10% threshold identifies instances where the over-provisioning is extreme enough that a recommendation carries low risk.

**Why post recommendations to Slack rather than automatically resizing instances?**  
Automatic rightsizing without human approval is operationally dangerous: an instance that looks under-utilized may be under-utilized because it's waiting for a scheduled batch job that runs weekly. An instance tagged `environment=production` should never be automatically resized. Human review converts a potentially harmful automated action into a reviewed, approved decision. The Lambda analyst provides the analysis; the engineer provides the judgment.

### Step 4 — Spot Instance Strategy

```hcl
# terraform/spot-strategy/main.tf
resource "aws_autoscaling_group" "mixed_instances" {
  name             = "application-mixed"
  min_size         = 2
  max_size         = 10
  desired_capacity = 4
  
  # On-demand instances for guaranteed baseline capacity
  on_demand_base_capacity                  = 2   # always 2 on-demand
  on_demand_percentage_above_base_capacity = 0   # burst entirely on spot
  
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  
  mixed_instances_policy {
    instances_distribution {
      spot_allocation_strategy = "capacity-optimized"
      # capacity-optimized: picks the instance pool with most available
      # capacity → lowest interruption probability
    }
    
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.app.id
      }
      
      # Diverse instance types: if one type has no spot capacity, use another
      override {
        instance_type = "m5.large"
      }
      override {
        instance_type = "m5a.large"
      }
      override {
        instance_type = "m4.large"
      }
    }
  }
}
```

**Why `capacity-optimized` allocation strategy rather than `price-capacity-optimized` or `lowest-price`?**  
`lowest-price` selects the cheapest spot pool — which is often cheap because it has high interruption probability (AWS needs that capacity back frequently). `capacity-optimized` selects the pool with the most available spare capacity — AWS is less likely to interrupt instances in pools where it has plenty of capacity to give. For production workloads, a 2% higher spot price is worth significantly lower interruption probability. `price-capacity-optimized` is the balanced option, but `capacity-optimized` is recommended for workloads that are sensitive to interruption.

**Why three instance type overrides (m5.large, m5a.large, m4.large)?**  
Spot capacity is pool-specific: `m5.large` in `us-east-1a` is a different pool from `m5.large` in `us-east-1b`, and from `m5a.large` in `us-east-1a`. If you request only `m5.large`, you're competing in fewer pools — a capacity shortage in `m5.large` pools leaves you unable to acquire spot instances. Three instance type families that have nearly identical performance characteristics means the ASG can acquire capacity from 9+ pools (3 types × 3 AZs), dramatically improving spot capacity availability.

### Step 5 — Kubernetes Resource Controls

```yaml
# policies/resource-quotas.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "4"          # team-a can request at most 4 vCPUs total
    requests.memory: 8Gi       # and 8GB memory total
    limits.cpu: "8"            # hard limit: 8 vCPUs total
    limits.memory: 16Gi
    count/pods: "20"           # max 20 pods in this namespace
---
# policies/limit-ranges.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-a
spec:
  limits:
    - type: Container
      default:              # applied if container doesn't specify limits
        cpu: 500m
        memory: 512Mi
      defaultRequest:       # applied if container doesn't specify requests
        cpu: 100m
        memory: 128Mi
      max:                  # individual container hard cap
        cpu: "2"
        memory: 2Gi
```

**Why ResourceQuota at the namespace level rather than per-pod limits only?**  
Per-pod limits prevent a single runaway container from consuming all node resources. But without namespace-level quotas, a team can deploy 100 pods each within its individual limits — consuming far more than the team's fair share of cluster resources. ResourceQuota enforces the team's total allocation; LimitRange enforces individual pod behavior. Both are necessary: quota without limits allows one pod to take everything; limits without quota allow many small pods to take everything.

**Why LimitRange `default` and `defaultRequest` rather than requiring developers to always set resource specifications?**  
A pod deployed without resource requests has undefined resource requirements from Kubernetes' perspective — the scheduler cannot make informed placement decisions, and HPA cannot compute utilization. Requiring developers to always specify resources creates friction and is rarely enforced. LimitRange defaults automatically apply sensible values to pods that don't specify resources, ensuring every pod has resource requests set without developer action.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Budget alerts at 80%:** Teams have advance warning and time to investigate before the budget is exceeded
- **Weekly rightsizing reports to Slack:** Cost optimization is a visible, recurring team activity, not a quarterly audit

### Security
- **Tagging as mandatory governance:** Cost attribution requires consistent tagging; tagging compliance is enforced via AWS Config rules, creating an indirect security benefit (untagged resources are unowned resources — nobody is responsible for their security posture)

### Reliability
- **On-demand baseline (2 instances):** Spot instances can be interrupted with 2-minute notice; the on-demand baseline ensures minimum capacity is always available regardless of spot availability
- **Diverse instance type pool:** Three instance types × three AZs = 9 spot capacity pools; interruption of any single pool doesn't leave the application without capacity

### Performance Efficiency
- **`capacity-optimized` spot strategy:** Lower interruption probability = more stable performance; spot interruptions cause brief availability dips that degrade p99 latency
- **LimitRange defaults:** Pods with defined resource requests enable accurate scheduler placement; pods without requests may be placed on nodes that are already resource-constrained

### Cost Optimization
- **20-30% EC2 savings from rightsizing:** 14-day average CPU analysis identifies instances where over-provisioning is certain, not speculative
- **60-90% savings on spot vs on-demand:** Non-critical burst capacity at a fraction of on-demand cost
- **Athena with Parquet CUR:** Query costs reduced 10× from format and columnar storage — cost visibility doesn't have to be expensive

### Sustainability
- **Rightsizing reduces idle compute:** Over-provisioned instances consume power for unused CPU cycles; rightsizing reduces the physical energy footprint proportionally to the over-provisioning reduction

---

## Key Architectural Insight

The most powerful FinOps intervention is not spot instances or rightsizing — it is **tagging**. Without tags, cost attribution requires manual investigation: which EC2 instances belong to which team? which RDS clusters serve which application? Tagging makes cost allocation automatic. Once costs are attributed, budget alerts create accountability (teams know their spend before the bill arrives), rightsizing analysis identifies specific targets (not just "EC2 is expensive" but "instance i-0abc123 has been at 4% CPU for two weeks"), and anomaly detection catches unexpected growth before it becomes a budget crisis. The 70% cost reduction in Lab 17 and the 40% reduction in Lab 19 are built on a foundation of consistent tagging — without it, neither the analysis nor the governance would be possible.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
