# Phase 11: Service Mesh & Advanced Networking

**Difficulty:** Expert | **Time:** 6-8 hours | **Prerequisites:** Phase 10

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

A service mesh adds a transparent infrastructure layer that handles service-to-service communication without changing application code. Istio injects a sidecar proxy (Envoy) into every pod, providing mTLS encryption, traffic management, and observability automatically.

### What the Service Mesh Provides

```
┌─────────────────────────────────────────────────────────────┐
│                     Service Mesh (Istio)                     │
│                                                             │
│  ┌─────────────┐      mTLS       ┌─────────────┐          │
│  │ User Service│◄──────────────►│Order Service │          │
│  │ ┌─────────┐ │                 │ ┌─────────┐ │          │
│  │ │  App    │ │                 │ │  App    │ │          │
│  │ └────┬────┘ │                 │ └────┬────┘ │          │
│  │ ┌────┴────┐ │                 │ ┌────┴────┐ │          │
│  │ │ Envoy   │ │                 │ │ Envoy   │ │          │
│  │ │ Sidecar │ │                 │ │ Sidecar │ │          │
│  │ └─────────┘ │                 │ └─────────┘ │          │
│  └─────────────┘                 └─────────────┘          │
│                                                             │
│  Features:                                                  │
│  ├── mTLS — Encrypted service-to-service communication      │
│  ├── Traffic Management — Canary, blue/green, A/B testing    │
│  ├── Circuit Breaking — Connection pool limits, outlier      │
│  │                       detection                          │
│  ├── Canary Deployments — Automated progressive delivery     │
│  └── Observability — Request-level metrics, traces           │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
phase-11-service-mesh/
├── istio/
│   └── peer-authentication.yaml   # mTLS + VirtualService + DestinationRule
└── canary/
    └── canary-release.yaml        # Flagger canary deployment
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| istioctl | 1.20+ | `brew install istioctl` |
| Helm | 3.13+ | Installed in Phase 6 |
| kubectl | 1.28+ | Installed in Phase 4 |

### Install Istio

```bash
# Install Istio with the production profile
istioctl install --set profile=default -y

# Enable sidecar injection for the production namespace
kubectl label namespace production istio-injection=enabled

# Verify Istio installation
istioctl verify-install

# Restart existing deployments to inject sidecars
kubectl rollout restart deployment -n production
```

### Install Flagger (for canary deployments)

```bash
helm repo add flagger https://flagger.app
helm install flagger flagger/flagger \
  --namespace istio-system \
  --set meshProvider=istio \
  --set metricsServer=http://monitoring-kube-prometheus-prometheus.monitoring:9090
```

---

## 3. Step-by-Step Implementation

### Step 1: Enable Strict mTLS

Apply the PeerAuthentication policy:

```bash
kubectl apply -f istio/peer-authentication.yaml
```

Verify mTLS is active:

```bash
# Check mTLS status for all workloads
istioctl x describe pod $(kubectl get pod -n production -l app=user-service -o jsonpath='{.items[0].metadata.name}') -n production

# Expected: STRICT mTLS enabled

# Verify encrypted connections
istioctl proxy-config clusters $(kubectl get pod -n production -l app=user-service -o jsonpath='{.items[0].metadata.name}') -n production | grep STRICT
```

### Step 2: Configure Traffic Routing

The VirtualService and DestinationRule define how traffic flows between service versions:

```bash
# Already applied as part of peer-authentication.yaml (multi-document YAML)
# Verify routing rules
istioctl analyze -n production
```

Test canary routing:

```bash
# Standard traffic — goes to stable (95%)
curl -sf https://api.ecommerce.com/api/users/health

# Canary header — forces traffic to canary version
curl -sf -H "x-canary: true" https://api.ecommerce.com/api/users/health
```

### Step 3: Deploy a Canary Release

Apply the Flagger Canary resource:

```bash
kubectl apply -f canary/canary-release.yaml
```

Trigger a canary deployment:

```bash
# Update the image tag to trigger Flagger
kubectl set image deployment/user-service \
  user-service=123456789.dkr.ecr.us-east-1.amazonaws.com/user-service:v2.0.0 \
  -n production

# Watch Flagger progress the canary
kubectl describe canary user-service -n production

# Monitor traffic weight progression
watch kubectl get canary -n production
```

**Expected canary progression:**

```
NAME           STATUS        WEIGHT   LASTTRANSITIONTIME
user-service   Progressing   0        2024-01-15T10:00:00Z
user-service   Progressing   10       2024-01-15T10:01:00Z
user-service   Progressing   20       2024-01-15T10:02:00Z
user-service   Progressing   30       2024-01-15T10:03:00Z
...
user-service   Progressing   50       2024-01-15T10:05:00Z
user-service   Succeeded     0        2024-01-15T10:15:00Z   ← Promoted
```

### Step 4: Test Automated Rollback

```bash
# Deploy a broken version to trigger rollback
kubectl set image deployment/user-service \
  user-service=123456789.dkr.ecr.us-east-1.amazonaws.com/user-service:v2.0.0-broken \
  -n production

# Flagger should detect metric failures and rollback
watch kubectl get canary -n production

# Expected:
# user-service   Failed   0   ← Rolled back to stable
```

---

## 4. Configuration Walkthrough

### `istio/peer-authentication.yaml` — Three Resources

#### 1. PeerAuthentication — mTLS Enforcement

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production           # Applies to ALL pods in the production namespace
spec:
  mtls:
    mode: STRICT                  # Reject any non-mTLS traffic
                                   # All service-to-service calls must be encrypted
                                   # Istio manages certificate issuance and rotation
```

`STRICT` mode means:
- Every connection between pods in the `production` namespace is TLS-encrypted
- Certificates are automatically issued by Istio's CA (Citadel)
- Certificate rotation happens automatically (default 24-hour validity)
- Non-mesh clients (external traffic) must go through the Ingress Gateway

#### 2. VirtualService — Traffic Routing

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-service
  namespace: production
spec:
  hosts:
    - user-service                 # Match requests to this service

  http:
    # Rule 1: Header-based routing for canary testing
    - match:
        - headers:
            x-canary:
              exact: "true"        # If x-canary: true header is present
      route:
        - destination:
            host: user-service
            subset: canary         # Send 100% to canary version

    # Rule 2: Default weighted routing
    - route:
        - destination:
            host: user-service
            subset: stable
          weight: 95               # 95% of traffic to stable version
        - destination:
            host: user-service
            subset: canary
          weight: 5                # 5% of traffic to canary version
```

#### 3. DestinationRule — Connection Management

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: user-service
  namespace: production
spec:
  host: user-service

  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100        # Maximum TCP connections per pod
      http:
        h2UpgradePolicy: DEFAULT   # Allow HTTP/2 upgrade
        http1MaxPendingRequests: 100  # Queue up to 100 requests
        http2MaxRequests: 1000     # Max concurrent HTTP/2 requests

    outlierDetection:
      consecutive5xxErrors: 5      # Eject after 5 consecutive 5xx errors
      interval: 30s               # Check every 30 seconds
      baseEjectionTime: 30s       # Eject for at least 30 seconds
      maxEjectionPercent: 50      # Never eject more than 50% of pods

  subsets:
    - name: stable
      labels:
        version: stable            # Pods with label version=stable
    - name: canary
      labels:
        version: canary            # Pods with label version=canary
```

### `canary/canary-release.yaml` — Flagger Canary

Key configuration from the Flagger Canary resource:

```yaml
analysis:
  interval: 1m                     # Run analysis every minute
  threshold: 5                     # Fail after 5 failed checks
  maxWeight: 50                    # Maximum canary traffic weight
  stepWeight: 10                   # Increase by 10% each step

  metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99                    # At least 99% success rate
      interval: 1m

    - name: request-duration
      thresholdRange:
        max: 500                   # P99 latency under 500ms
      interval: 1m

  webhooks:
    - name: smoke-test
      type: pre-rollout            # Run before canary starts
      url: http://flagger-loadtester/

    - name: load-test
      type: rollout                # Run during canary progression
      url: http://flagger-loadtester/
      metadata:
        cmd: "hey -z 1m -q 10 -c 2 http://user-service-canary.production:3000/health"
```

Flagger automates the canary process:
1. Deploy new version as canary (0% traffic)
2. Run pre-rollout smoke tests
3. Shift 10% traffic to canary
4. Analyze metrics (success rate, latency)
5. If metrics pass → increase to 20%, 30%, ... 50%
6. If metrics fail → rollback to stable, send Slack notification
7. After sustained success at max weight → promote canary to stable

---

## 5. Verification Checklist

- [ ] Istio installed: `istioctl verify-install`
- [ ] Sidecar injection enabled: `kubectl get ns production -o yaml | grep istio-injection`
- [ ] All pods have 2/2 containers (app + Envoy): `kubectl get pods -n production`
- [ ] mTLS is STRICT: `istioctl x describe pod <pod> -n production`
- [ ] VirtualService applied: `kubectl get virtualservice -n production`
- [ ] DestinationRule applied: `kubectl get destinationrule -n production`
- [ ] Stable traffic routing works: `curl https://api.ecommerce.com/api/users/health`
- [ ] Canary header routing works: `curl -H "x-canary: true" https://api.ecommerce.com/api/users/health`
- [ ] Flagger installed: `kubectl get pods -n istio-system -l app.kubernetes.io/name=flagger`
- [ ] Canary resource created: `kubectl get canary -n production`
- [ ] Canary deployment progresses through weight steps
- [ ] Failed canary triggers automatic rollback
- [ ] Circuit breaker ejects unhealthy pods (outlier detection working)
- [ ] Kiali dashboard shows service mesh topology (if installed)

---

## 6. Troubleshooting

### Pods stuck at 1/2 Ready (sidecar not injecting)

```bash
# Verify namespace label
kubectl get ns production --show-labels | grep istio-injection

# If missing:
kubectl label namespace production istio-injection=enabled

# Restart deployments to pick up the sidecar
kubectl rollout restart deployment -n production
```

### mTLS connection refused between services

```bash
# Check if both source and destination have sidecars
istioctl proxy-status

# Check for PeerAuthentication conflicts
kubectl get peerauthentication --all-namespaces

# Check Envoy proxy logs
kubectl logs <pod-name> -n production -c istio-proxy
```

### Canary stuck at 0% weight

```bash
# Check Flagger logs
kubectl logs -n istio-system -l app.kubernetes.io/name=flagger

# Check canary status
kubectl describe canary user-service -n production

# Common causes:
# 1. Metrics not available (Prometheus not scraping)
# 2. Primary deployment not ready
# 3. Webhook URL incorrect
```

### High latency after enabling Istio

```bash
# Check Envoy proxy resource usage
kubectl top pods -n production --containers

# Increase sidecar resources if needed
kubectl annotate pod <pod-name> \
  sidecar.istio.io/proxyCPU=200m \
  sidecar.istio.io/proxyMemory=256Mi
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Istio vs. Linkerd** | Istio | Linkerd | Feature-rich (traffic management, security policies). Trade-off: heavier resource overhead. |
| **Flagger vs. Argo Rollouts** | Flagger | Argo Rollouts | Native Istio integration, metric-driven automation. Trade-off: Argo Rollouts has more rollout strategies. |
| **STRICT mTLS** | Strict | Permissive | Zero-trust security. Trade-off: all clients must have sidecars. |
| **50% max canary weight** | 50% | 100% | Limits blast radius during canary. Trade-off: slower rollout. |
| **Outlier detection** | 5 consecutive errors | Single error | Avoids ejecting pods on transient errors. Trade-off: slower reaction to persistent failures. |

---

## 8. Production Considerations

- **Resource overhead** — Each Envoy sidecar adds ~50MB memory and ~10m CPU; plan node capacity accordingly
- **Sidecar lifecycle** — Configure `holdApplicationUntilProxyStarts: true` to prevent race conditions during startup
- **External services** — Define `ServiceEntry` resources for external APIs (payment gateways, email providers) so Istio can manage their traffic
- **Rate limiting** — Use Istio's `EnvoyFilter` or `WasmPlugin` for per-service rate limiting
- **Kiali dashboard** — Install Kiali for real-time service mesh visualization and traffic flow analysis
- **Authorization policies** — Add Istio `AuthorizationPolicy` resources for fine-grained service-to-service access control
- **Canary metrics** — Add custom business metrics (order conversion rate, payment success rate) to Flagger analysis

---

## 9. Next Phase

**[Phase 12: Multi-Region & Disaster Recovery →](../phase-12-multi-region/README.md)**

With service mesh securing and managing traffic within the cluster, Phase 12 extends the architecture to multiple AWS regions — active-passive failover with Route 53, Aurora Global Database, and validated disaster recovery runbooks.

---

[← Phase 10: Chaos Engineering](../phase-10-chaos/README.md) | [Back to Project Overview](../README.md) | [Phase 12: Multi-Region →](../phase-12-multi-region/README.md)
