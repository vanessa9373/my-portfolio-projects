# Regional Failover Runbook

**Service:** E-Commerce Platform
**Last Updated:** 2026-02-27
**Owner:** Platform Engineering
**Severity:** SEV-1
**Expected Duration:** 15-30 minutes (automated), 30-60 minutes (manual)

---

## Table of Contents

1. [Prerequisites Checklist](#1-prerequisites-checklist)
2. [Automated Failover (Route 53 Health Check)](#2-automated-failover-route-53-health-check)
3. [Manual Failover Procedure](#3-manual-failover-procedure)
4. [Aurora Global Database Failover](#4-aurora-global-database-failover)
5. [Velero Restore from Backup](#5-velero-restore-from-backup)
6. [DNS Propagation Verification](#6-dns-propagation-verification)
7. [Validation Checklist](#7-validation-checklist)
8. [Rollback Procedure](#8-rollback-procedure)
9. [Communication Template](#9-communication-template)
10. [Post-Incident Review Template](#10-post-incident-review-template)

---

## 1. Prerequisites Checklist

Before initiating failover, confirm the following conditions are met:

### Infrastructure Readiness

- [ ] Secondary region (us-west-2) EKS cluster is healthy: `kubectl --context us-west-2 get nodes`
- [ ] Secondary region node count meets minimum capacity (at least 6 nodes across 3 AZs)
- [ ] Cross-region VPC peering or Transit Gateway is operational
- [ ] Secondary region load balancers (ALB/NLB) are provisioned and passing health checks
- [ ] IAM roles and service accounts are replicated to the secondary region
- [ ] Container images are available in the secondary region ECR registry
- [ ] Secrets Manager secrets are replicated to the secondary region

### Data Readiness

- [ ] Aurora Global Database secondary cluster is in `available` state
- [ ] Replication lag is below 100ms: `aws rds describe-global-clusters --global-cluster-identifier ecommerce-global`
- [ ] ElastiCache Global Datastore secondary is in `associated` state
- [ ] S3 Cross-Region Replication is current (check replication metrics in CloudWatch)
- [ ] Velero backup completed within the last 15 minutes: `velero backup get --output json | jq '.items[0].status'`

### Networking Readiness

- [ ] Route 53 health checks are configured and active for both regions
- [ ] DNS TTL has been lowered to 60 seconds (should be pre-configured)
- [ ] CloudFront distribution includes the secondary region origin
- [ ] WAF rules are replicated to the secondary region
- [ ] ACM certificates are provisioned in the secondary region

### Team Readiness

- [ ] On-call engineer has access to both region AWS consoles
- [ ] Incident channel is open in Slack (#incident-response)
- [ ] Incident commander has been notified
- [ ] Customer support team has been alerted to potential impact

---

## 2. Automated Failover (Route 53 Health Check)

The platform is configured for automated failover via Route 53 health checks. Under normal conditions, failover triggers automatically when the primary region becomes unhealthy.

### How Automated Failover Works

1. **Health Check Monitoring:** Route 53 health checks poll the primary region's ALB endpoint (`api.ecommerce.com`) every 10 seconds from multiple global locations.

2. **Failure Detection:** If 3 consecutive health checks fail (30 seconds), Route 53 marks the primary endpoint as unhealthy.

3. **DNS Failover:** Route 53 automatically updates the DNS record to point to the secondary region's ALB endpoint. With a 60-second TTL, most clients resolve to the new region within 1-2 minutes.

4. **Alert Trigger:** CloudWatch alarm `route53-failover-triggered` fires and notifies the on-call team via PagerDuty.

### Verifying Automated Failover Status

```bash
# Check Route 53 health check status
aws route53 get-health-check-status \
  --health-check-id HC_PRIMARY_REGION_ID

# Check current DNS resolution
dig +short api.ecommerce.com
dig +short api.ecommerce.com @8.8.8.8

# Verify which region is receiving traffic
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/ecommerce-alb/XXXXX \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --region us-east-1

# Same query for secondary region
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/ecommerce-alb/YYYYY \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --region us-west-2
```

### If Automated Failover Did NOT Trigger

If the primary region is degraded but Route 53 has not triggered failover (e.g., health checks are passing but the application is partially broken), proceed to the manual failover procedure in Section 3.

---

## 3. Manual Failover Procedure

Use this procedure when automated failover has not triggered but the primary region is degraded or an impending failure is anticipated (e.g., AWS status page reports regional issues).

### Step 1: Declare the Incident

```bash
# Notify the team
# Post in #incident-response Slack channel:
# "@oncall-platform SEV-1: Initiating manual regional failover from us-east-1 to us-west-2. Reason: [REASON]"
```

### Step 2: Verify Secondary Region Readiness

```bash
# Verify EKS cluster health in secondary region
kubectl --context us-west-2-ecommerce-prod get nodes -o wide
kubectl --context us-west-2-ecommerce-prod get pods -n ecommerce-prod --field-selector=status.phase!=Running

# Verify all deployments are scaled appropriately
kubectl --context us-west-2-ecommerce-prod get deployments -n ecommerce-prod

# Check Aurora secondary cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier ecommerce-secondary \
  --region us-west-2 \
  --query 'DBClusters[0].Status'

# Check replication lag
aws rds describe-global-clusters \
  --global-cluster-identifier ecommerce-global \
  --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`false`].GlobalWriteForwardingStatus'
```

### Step 3: Scale Up Secondary Region

```bash
# Scale deployments to production capacity
kubectl --context us-west-2-ecommerce-prod scale deployment user-service \
  --replicas=6 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment order-service \
  --replicas=6 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment product-service \
  --replicas=4 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment payment-service \
  --replicas=4 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment notification-service \
  --replicas=3 -n ecommerce-prod

# Wait for all pods to be ready
kubectl --context us-west-2-ecommerce-prod wait --for=condition=ready pod \
  --all -n ecommerce-prod --timeout=300s
```

### Step 4: Perform Aurora Global Database Failover

See [Section 4](#4-aurora-global-database-failover) for detailed steps.

### Step 5: Update DNS to Secondary Region

```bash
# Force Route 53 failover by setting the primary health check to unhealthy
aws route53 update-health-check \
  --health-check-id HC_PRIMARY_REGION_ID \
  --disabled

# Alternatively, directly update the DNS record (if not using failover routing)
aws route53 change-resource-record-sets \
  --hosted-zone-id Z_HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.ecommerce.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z_ALB_HOSTED_ZONE_US_WEST_2",
          "DNSName": "ecommerce-alb-us-west-2.us-west-2.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        },
        "SetIdentifier": "primary",
        "Failover": "PRIMARY"
      }
    }]
  }'

# Record the change ID for tracking
# Change ID will be in the response: /change/C_CHANGE_ID
```

### Step 6: Verify DNS Propagation

See [Section 6](#6-dns-propagation-verification) for detailed steps.

### Step 7: Validate Services

See [Section 7](#7-validation-checklist) for the full validation checklist.

---

## 4. Aurora Global Database Failover

### Planned Failover (Primary Region Still Accessible)

Use planned failover when the primary region is still reachable but you want to proactively move writes to the secondary region.

```bash
# Initiate planned failover (zero data loss)
aws rds failover-global-cluster \
  --global-cluster-identifier ecommerce-global \
  --target-db-cluster-identifier arn:aws:rds:us-west-2:ACCOUNT_ID:cluster:ecommerce-secondary \
  --region us-east-1

# Monitor failover progress (takes 1-3 minutes for planned failover)
watch -n 5 "aws rds describe-global-clusters \
  --global-cluster-identifier ecommerce-global \
  --query 'GlobalClusters[0].GlobalClusterMembers[*].{ARN:DBClusterArn,Writer:IsWriter,Status:GlobalWriteForwardingStatus}' \
  --output table"
```

### Unplanned Failover (Primary Region Unavailable)

Use unplanned failover when the primary region is completely unreachable.

```bash
# Step 1: Detach the secondary cluster from the global database
aws rds remove-from-global-cluster \
  --global-cluster-identifier ecommerce-global \
  --db-cluster-identifier arn:aws:rds:us-west-2:ACCOUNT_ID:cluster:ecommerce-secondary \
  --region us-west-2

# Step 2: The detached cluster automatically becomes a standalone writer
# Monitor until the cluster status is "available" and the writer endpoint is active
watch -n 5 "aws rds describe-db-clusters \
  --db-cluster-identifier ecommerce-secondary \
  --region us-west-2 \
  --query 'DBClusters[0].{Status:Status,Endpoint:Endpoint,ReaderEndpoint:ReaderEndpoint}' \
  --output table"

# Step 3: Update application configuration to use the new writer endpoint
kubectl --context us-west-2-ecommerce-prod set env deployment/user-service \
  DB_HOST=ecommerce-secondary.cluster-xxxxx.us-west-2.rds.amazonaws.com \
  -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod set env deployment/order-service \
  DB_HOST=ecommerce-secondary.cluster-xxxxx.us-west-2.rds.amazonaws.com \
  -n ecommerce-prod
```

### Post-Failover Verification

```bash
# Verify write capability
kubectl --context us-west-2-ecommerce-prod exec -it deploy/user-service \
  -n ecommerce-prod -- \
  curl -sf localhost:8080/api/v1/health/db | jq '.writable'

# Check replication status
aws rds describe-db-clusters \
  --db-cluster-identifier ecommerce-secondary \
  --region us-west-2 \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}'
```

---

## 5. Velero Restore from Backup

Use Velero to restore Kubernetes resources if the secondary region does not have a hot standby or if stateful workloads need restoration.

### Step 1: List Available Backups

```bash
# List recent backups
velero backup get --kubecontext us-west-2-ecommerce-prod

# Get details of the most recent backup
velero backup describe ecommerce-prod-latest \
  --kubecontext us-west-2-ecommerce-prod \
  --details
```

### Step 2: Restore from Backup

```bash
# Restore all resources in the ecommerce-prod namespace
velero restore create ecommerce-dr-restore \
  --from-backup ecommerce-prod-latest \
  --namespace-mappings ecommerce-prod:ecommerce-prod \
  --include-namespaces ecommerce-prod \
  --restore-volumes=true \
  --kubecontext us-west-2-ecommerce-prod

# Monitor restore progress
velero restore describe ecommerce-dr-restore \
  --kubecontext us-west-2-ecommerce-prod \
  --details

# Wait for restore to complete
watch -n 10 "velero restore get ecommerce-dr-restore \
  --kubecontext us-west-2-ecommerce-prod \
  -o json | jq '.status.phase'"
```

### Step 3: Verify Restored Resources

```bash
# Check all pods are running
kubectl --context us-west-2-ecommerce-prod get pods -n ecommerce-prod

# Check PersistentVolumeClaims are bound
kubectl --context us-west-2-ecommerce-prod get pvc -n ecommerce-prod

# Check ConfigMaps and Secrets are restored
kubectl --context us-west-2-ecommerce-prod get configmaps,secrets -n ecommerce-prod

# Verify CRDs are restored
kubectl --context us-west-2-ecommerce-prod get virtualservices,destinationrules -n ecommerce-prod
```

---

## 6. DNS Propagation Verification

### Verify DNS Resolution

```bash
# Check resolution from multiple DNS providers
echo "=== Google DNS ===" && dig +short api.ecommerce.com @8.8.8.8
echo "=== Cloudflare DNS ===" && dig +short api.ecommerce.com @1.1.1.1
echo "=== OpenDNS ===" && dig +short api.ecommerce.com @208.67.222.222
echo "=== AWS DNS ===" && dig +short api.ecommerce.com @169.254.169.253

# Verify the resolved IP belongs to the secondary region
aws ec2 describe-network-interfaces \
  --filters Name=addresses.association.public-ip,Values=$(dig +short api.ecommerce.com @8.8.8.8) \
  --region us-west-2 \
  --query 'NetworkInterfaces[0].AvailabilityZone'

# Check TTL remaining on DNS records
dig api.ecommerce.com +noall +answer

# Verify Route 53 change has propagated
aws route53 get-change --id /change/C_CHANGE_ID \
  --query 'ChangeInfo.Status'
```

### Monitor DNS Propagation Globally

```bash
# Use Route 53 test DNS answer to verify from Route 53's perspective
aws route53 test-dns-answer \
  --hosted-zone-id Z_HOSTED_ZONE_ID \
  --record-name api.ecommerce.com \
  --record-type A

# Check propagation status (repeat every 30 seconds until INSYNC)
while true; do
  STATUS=$(aws route53 get-change --id /change/C_CHANGE_ID --query 'ChangeInfo.Status' --output text)
  echo "$(date): DNS change status: $STATUS"
  if [ "$STATUS" = "INSYNC" ]; then
    echo "DNS propagation complete."
    break
  fi
  sleep 30
done
```

---

## 7. Validation Checklist

After failover, verify the following before declaring the failover successful.

### Health Checks

- [ ] ALB health checks passing for all target groups in us-west-2
- [ ] All Kubernetes pods in `Running` state: `kubectl get pods -n ecommerce-prod --field-selector=status.phase!=Running` returns empty
- [ ] All deployments have desired replica count: `kubectl get deployments -n ecommerce-prod`
- [ ] Readiness probes passing for all services
- [ ] Istio sidecar proxies are healthy: `istioctl proxy-status`

### API Endpoint Verification

```bash
# Test each service endpoint
curl -sf https://api.ecommerce.com/api/v1/users/health | jq .
curl -sf https://api.ecommerce.com/api/v1/orders/health | jq .
curl -sf https://api.ecommerce.com/api/v1/products/health | jq .
curl -sf https://api.ecommerce.com/api/v1/payments/health | jq .

# Run synthetic transaction (place a test order)
curl -sf -X POST https://api.ecommerce.com/api/v1/orders/synthetic-test \
  -H "Authorization: Bearer $SYNTHETIC_TEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"test": true, "product_id": "test-product-001", "quantity": 1}'
```

### Data Integrity

- [ ] Database writes are succeeding (test insert and read-back)
- [ ] No data loss detected: compare last order ID in primary vs. secondary
- [ ] ElastiCache is warm and responding: `redis-cli -h elasticache-endpoint ping`
- [ ] S3 objects are accessible from the secondary region
- [ ] Message queues (SQS/SNS) are processing in the secondary region

### Latency Verification

```bash
# Check P99 latency from CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace ECommerce/API \
  --metric-name Latency \
  --dimensions Name=Service,Value=user-service \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics p99 \
  --region us-west-2

# Verify latency is within acceptable bounds (< 500ms P99)
```

### Monitoring and Alerting

- [ ] Prometheus is scraping targets in the secondary region
- [ ] Grafana dashboards show data from the secondary region
- [ ] PagerDuty alerts are routing correctly
- [ ] Log aggregation (Fluent Bit) is shipping logs from the secondary region
- [ ] Distributed tracing (Jaeger/X-Ray) is capturing traces

---

## 8. Rollback Procedure

If the failover introduces new issues or the primary region recovers, follow this procedure to fail back.

### Pre-Rollback Checks

- [ ] Primary region is fully healthy and accessible
- [ ] Primary region EKS cluster nodes are ready
- [ ] Primary region Aurora cluster can accept writes
- [ ] No in-flight transactions that would be disrupted

### Rollback Steps

```bash
# Step 1: Resync data from secondary to primary
# For Aurora: re-add the original primary as a secondary to the global cluster
aws rds create-global-cluster \
  --global-cluster-identifier ecommerce-global-v2 \
  --source-db-cluster-identifier arn:aws:rds:us-west-2:ACCOUNT_ID:cluster:ecommerce-secondary

aws rds create-db-cluster \
  --db-cluster-identifier ecommerce-primary-restored \
  --global-cluster-identifier ecommerce-global-v2 \
  --engine aurora-postgresql \
  --engine-version 15.4 \
  --region us-east-1

# Step 2: Wait for replication to catch up
watch -n 10 "aws rds describe-global-clusters \
  --global-cluster-identifier ecommerce-global-v2 \
  --query 'GlobalClusters[0].GlobalClusterMembers[*].{ARN:DBClusterArn,Writer:IsWriter}' \
  --output table"

# Step 3: Perform planned failover back to primary
aws rds failover-global-cluster \
  --global-cluster-identifier ecommerce-global-v2 \
  --target-db-cluster-identifier arn:aws:rds:us-east-1:ACCOUNT_ID:cluster:ecommerce-primary-restored

# Step 4: Re-enable Route 53 health check for primary
aws route53 update-health-check \
  --health-check-id HC_PRIMARY_REGION_ID \
  --no-disabled

# Step 5: Verify DNS resolves to primary region
dig +short api.ecommerce.com @8.8.8.8

# Step 6: Scale down secondary region to warm standby
kubectl --context us-west-2-ecommerce-prod scale deployment user-service \
  --replicas=2 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment order-service \
  --replicas=2 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment product-service \
  --replicas=2 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment payment-service \
  --replicas=2 -n ecommerce-prod
kubectl --context us-west-2-ecommerce-prod scale deployment notification-service \
  --replicas=1 -n ecommerce-prod
```

---

## 9. Communication Template

### Internal Notification (Slack / PagerDuty)

```
INCIDENT: Regional Failover - E-Commerce Platform
Severity: SEV-1
Status: [IN PROGRESS / RESOLVED]
Time: [YYYY-MM-DD HH:MM UTC]
Impact: [DESCRIPTION OF USER-FACING IMPACT]
Primary Region: us-east-1 (DEGRADED/DOWN)
Failover Region: us-west-2 (ACTIVE)
Incident Commander: [NAME]
Actions Taken:
  - [ACTION 1]
  - [ACTION 2]
Next Update: [TIME] or in [X] minutes
```

### External Status Page Update

```
Title: Service Disruption - E-Commerce Platform
Status: Investigating / Identified / Monitoring / Resolved

[INVESTIGATING]
We are investigating reports of degraded performance on our platform.
Some users may experience slower response times or intermittent errors.
Our engineering team is actively working on the issue.

[IDENTIFIED]
We have identified the root cause as a regional infrastructure issue
affecting our primary data center. We are initiating failover to our
disaster recovery site. Users may experience brief interruptions during
the transition.

[MONITORING]
Failover to our disaster recovery site has been completed. We are
monitoring system performance and verifying data integrity. Most
services have been restored. Users may experience slightly higher
latency as traffic is served from our secondary data center.

[RESOLVED]
The service disruption has been fully resolved. All systems are
operating normally. A detailed post-incident report will be published
within 48 hours.
```

### Customer Email Template

```
Subject: [Resolved] E-Commerce Platform Service Disruption - [DATE]

Dear Customer,

We want to inform you about a service disruption that occurred on
[DATE] between [START TIME] and [END TIME] UTC.

What happened:
[BRIEF DESCRIPTION]

Impact:
[DESCRIPTION OF CUSTOMER IMPACT - e.g., orders delayed, pages slow]

What we did:
Our systems automatically detected the issue and initiated failover
to our disaster recovery infrastructure. Our engineering team
monitored the process and verified all services were restored.

Data integrity:
[CONFIRM NO DATA LOSS / DESCRIBE ANY DATA IMPACT]

What we are doing to prevent this:
[LIST PREVENTIVE MEASURES]

We sincerely apologize for any inconvenience. If you have questions
or experienced specific issues during this window, please contact
our support team at support@ecommerce.com.

Best regards,
[NAME]
VP of Engineering
```

---

## 10. Post-Incident Review Template

### Incident Summary

| Field | Value |
|-------|-------|
| Incident ID | INC-YYYY-NNNN |
| Date | YYYY-MM-DD |
| Duration | X hours Y minutes |
| Severity | SEV-1 |
| Incident Commander | [NAME] |
| Services Affected | [LIST] |
| Customers Affected | [NUMBER / PERCENTAGE] |
| Revenue Impact | $[AMOUNT] estimated |

### Timeline

| Time (UTC) | Event |
|------------|-------|
| HH:MM | First alert triggered |
| HH:MM | On-call engineer acknowledged |
| HH:MM | Incident declared, commander assigned |
| HH:MM | Root cause identified |
| HH:MM | Failover initiated |
| HH:MM | DNS propagation complete |
| HH:MM | Services validated in secondary region |
| HH:MM | Incident resolved |
| HH:MM | Failback initiated |
| HH:MM | Failback complete, normal operations resumed |

### Root Cause Analysis

**What happened:**
[DETAILED DESCRIPTION]

**Why it happened:**
[5 WHYS ANALYSIS]

1. Why did the service go down? [ANSWER]
2. Why did [ANSWER 1] happen? [ANSWER]
3. Why did [ANSWER 2] happen? [ANSWER]
4. Why did [ANSWER 3] happen? [ANSWER]
5. Why did [ANSWER 4] happen? [ROOT CAUSE]

### What Went Well

- [ITEM 1]
- [ITEM 2]
- [ITEM 3]

### What Could Be Improved

- [ITEM 1]
- [ITEM 2]
- [ITEM 3]

### Action Items

| Action | Owner | Priority | Due Date | Status |
|--------|-------|----------|----------|--------|
| [ACTION 1] | [NAME] | P1 | YYYY-MM-DD | Open |
| [ACTION 2] | [NAME] | P2 | YYYY-MM-DD | Open |
| [ACTION 3] | [NAME] | P2 | YYYY-MM-DD | Open |

### Metrics

- **Time to Detect (TTD):** X minutes
- **Time to Respond (TTR):** X minutes
- **Time to Mitigate (TTM):** X minutes
- **Time to Resolve (full recovery):** X minutes
- **Error budget consumed:** X%
- **SLA impact:** [WITHIN SLA / BREACHED - details]
