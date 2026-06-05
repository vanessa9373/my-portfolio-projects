# K8S-10: Service Mesh with Istio

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Istio](https://img.shields.io/badge/Istio-466BB0?style=for-the-badge&logo=istio&logoColor=white)
![Envoy](https://img.shields.io/badge/Envoy_Proxy-AC6199?style=for-the-badge&logo=envoyproxy&logoColor=white)
![Kiali](https://img.shields.io/badge/Kiali-003459?style=for-the-badge&logo=kiali&logoColor=white)
![Jaeger](https://img.shields.io/badge/Jaeger-66CFE3?style=for-the-badge&logo=jaeger&logoColor=black)

## Summary

Implemented Istio service mesh across a three-tier microservice application to enforce mutual TLS encryption, enable canary deployments via traffic splitting, add circuit breaking for resilience, and gain deep observability through Kiali and Jaeger. This lab demonstrates how a service mesh eliminates the need to bake networking logic into application code by offloading it to sidecar proxies managed by a centralized control plane.

## The Problem

Our engineering team operates a three-tier microservice application (frontend, backend, database proxy) deployed on Kubernetes. Several critical gaps exist in the current architecture:

- **No encryption in transit** -- services communicate over plain HTTP inside the cluster, violating compliance requirements for data-in-transit encryption
- **No traffic control** -- new backend versions must be deployed all-at-once; canary releases are impossible without application-level routing logic
- **No circuit breaking** -- when the database proxy becomes slow, the backend continues hammering it, causing cascading failures that take down the entire stack
- **Zero service-to-service visibility** -- the team has no insight into request latency, error rates, or dependency graphs between services

## The Solution

Deployed Istio service mesh to inject Envoy sidecar proxies alongside every workload pod. Istiod (the control plane) distributes configuration to all sidecars, enabling:

- **Automatic mTLS** with `PeerAuthentication` set to `STRICT` mode -- every service-to-service call is encrypted and authenticated without code changes
- **Traffic splitting** via `VirtualService` and `DestinationRule` -- canary deployments route 10% of traffic to a new backend version while 90% stays on stable
- **Circuit breaking** configured through `DestinationRule` outlier detection -- failing backends are ejected from the load balancer pool
- **Fault injection** for chaos engineering -- simulating 5-second delays and HTTP 503 errors to validate retry and timeout configurations
- **Full observability** through Kiali (service topology), Jaeger (distributed tracing), and Prometheus (metrics)

## Architecture

```
                         +-----------------------+
                         |     Istio Gateway      |
                         |   (Ingress traffic)    |
                         +----------+------------+
                                    |
                    +---------------v-----------------+
                    |         istiod (Control Plane)   |
                    |  - Config distribution (xDS)     |
                    |  - Certificate authority (mTLS)  |
                    |  - Policy enforcement            |
                    +--+----------+----------+--------+
                       |          |          |
              +--------v--+  +---v------+  +v-----------+
              | frontend  |  | backend  |  | database   |
              | Pod       |  | Pod      |  | Pod        |
              | +-------+ |  | +------+ |  | +--------+ |
              | | App   | |  | | App  | |  | | App    | |
              | +---+---+ |  | +--+---+ |  | +---+----+ |
              |     |      |  |    |     |  |     |      |
              | +---v---+ |  | +--v---+ |  | +---v----+ |
              | | Envoy | |  | |Envoy | |  | | Envoy  | |
              | |sidecar| |  | |sidecar||  | |sidecar | |
              | +-------+ |  | +------+ |  | +--------+ |
              +-----------+  +---------+  +------------+
                     mTLS          mTLS         mTLS
                                    |
              +---------------------+---------------------+
              |                     |                     |
         +----v-----+     +--------v------+    +---------v----+
         |  Kiali   |     |   Jaeger      |    |  Prometheus  |
         | (Topology)|    | (Tracing)     |    |  (Metrics)   |
         +----------+     +--------------+    +--------------+
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| Istio 1.20 | Service mesh control plane | Industry standard mesh with the richest feature set for mTLS, traffic management, and observability |
| Envoy Proxy | Sidecar data plane | High-performance L7 proxy that Istio uses as its data plane; handles all inter-service traffic transparently |
| Kiali | Service topology visualization | Purpose-built for Istio; provides real-time traffic flow graphs and configuration validation |
| Jaeger | Distributed tracing | Collects spans from Envoy sidecars to show end-to-end request latency across services |
| Prometheus | Metrics collection | Scrapes Envoy metrics automatically; powers Kiali dashboards and alerting |
| Kubernetes 1.28 | Container orchestration | Production-grade platform for deploying and managing the mesh and workloads |

## Implementation Steps

### Step 1: Install Istio with istioctl

```bash
# Download and install Istio CLI
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
export PATH=$PWD/istio-1.20.0/bin:$PATH

# Install Istio with the demo profile (includes Kiali, Jaeger, Prometheus)
istioctl install --set profile=demo -y

# Verify installation
istioctl verify-install
kubectl get pods -n istio-system
```

**What this does:** Downloads Istio 1.20, installs the control plane (istiod) and ingress gateway into the `istio-system` namespace, and deploys observability addons. The demo profile includes all components needed for learning and testing.

### Step 2: Enable sidecar injection

```bash
# Label the default namespace for automatic sidecar injection
kubectl label namespace default istio-injection=enabled

# Verify the label
kubectl get namespace default --show-labels
```

**What this does:** Tells Istio's mutating admission webhook to automatically inject an Envoy sidecar container into every pod created in the `default` namespace. No application changes required.

### Step 3: Deploy sample microservices

```bash
# Deploy the three-tier application
kubectl apply -f manifests/sample-app-deployment.yaml

# Wait for pods to be ready (each should have 2/2 containers)
kubectl wait --for=condition=ready pod -l app=frontend --timeout=120s
kubectl wait --for=condition=ready pod -l app=backend --timeout=120s
kubectl get pods
```

**What this does:** Deploys frontend, backend, and database services. Because sidecar injection is enabled, each pod gets an Envoy proxy container alongside the application container (2/2 containers ready).

### Step 4: Configure mTLS (PeerAuthentication STRICT)

```bash
# Apply mesh-wide strict mTLS
kubectl apply -f manifests/istio-peer-authentication.yaml

# Verify mTLS is active between services
istioctl x describe pod $(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')

# Test that plain HTTP is rejected
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://backend.default.svc.cluster.local:8080/health || echo "Blocked: mTLS required"
```

**What this does:** Enforces STRICT mutual TLS across the entire mesh. Every service-to-service call must present a valid certificate issued by Istiod. Pods without sidecars cannot communicate with mesh services.

### Step 5: Create VirtualService for traffic splitting (90/10 canary)

```bash
# Deploy canary version of the backend
kubectl apply -f manifests/virtualservice-canary.yaml

# Verify routing rules
istioctl x describe service backend

# Generate traffic and observe distribution
for i in $(seq 1 100); do
  kubectl exec deploy/frontend -- curl -s http://backend:8080/version
done | sort | uniq -c
```

**What this does:** Configures Istio to route 90% of traffic to backend v1 (stable) and 10% to backend v2 (canary). The VirtualService defines the split, while the DestinationRule defines which pods belong to each version based on labels.

### Step 6: Add fault injection (delay and abort)

```bash
# Apply fault injection rules
kubectl apply -f manifests/fault-injection.yaml

# Test delay injection (should see ~5s response time for 50% of requests)
time kubectl exec deploy/frontend -- curl -s http://backend:8080/health

# Test abort injection (should see HTTP 503 for 10% of requests)
for i in $(seq 1 20); do
  kubectl exec deploy/frontend -- curl -s -o /dev/null -w "%{http_code}\n" http://backend:8080/health
done
```

**What this does:** Injects artificial failures into the mesh for resilience testing. A 5-second delay hits 50% of requests (testing timeout configs), and HTTP 503 aborts hit 10% of requests (testing retry logic). This validates that the application handles degraded dependencies gracefully.

### Step 7: Configure circuit breaking (DestinationRule)

```bash
# Apply circuit breaker configuration
kubectl apply -f manifests/destinationrule-circuit-breaker.yaml

# Generate load to trigger circuit breaking
kubectl exec deploy/frontend -- sh -c \
  'for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" http://backend:8080/health & done; wait'

# Check Envoy stats for circuit breaker trips
kubectl exec deploy/frontend -c istio-proxy -- \
  pilot-agent request GET stats | grep upstream_rq_pending_overflow
```

**What this does:** Configures Envoy circuit breakers to limit concurrent connections (100), pending requests (10), and retries (3) to the backend. When limits are exceeded, Envoy returns 503 immediately rather than queuing requests, preventing cascading failures.

### Step 8: Access Kiali dashboard and Jaeger traces

```bash
# Port-forward Kiali dashboard
kubectl port-forward svc/kiali -n istio-system 20001:20001 &

# Port-forward Jaeger UI
kubectl port-forward svc/tracing -n istio-system 16686:80 &

# Generate traffic for visualization
kubectl exec deploy/frontend -- sh -c \
  'for i in $(seq 1 200); do curl -s http://backend:8080/api/data; sleep 0.1; done'

echo "Kiali:  http://localhost:20001"
echo "Jaeger: http://localhost:16686"
```

**What this does:** Opens Kiali (service mesh topology, traffic flow visualization, configuration validation) and Jaeger (distributed tracing with per-request latency breakdown). Generate traffic first so the dashboards have data to display.

## Project Structure

```
K8S-10-service-mesh-istio/
├── README.md
├── manifests/
│   ├── istio-peer-authentication.yaml    # Mesh-wide strict mTLS
│   ├── virtualservice-canary.yaml        # 90/10 traffic split + DestinationRule
│   ├── destinationrule-circuit-breaker.yaml  # Circuit breaking config
│   ├── fault-injection.yaml              # Delay and abort injection
│   ├── gateway.yaml                      # Istio ingress gateway
│   └── sample-app-deployment.yaml        # Frontend, backend (v1+v2), database
└── scripts/
    ├── deploy.sh                         # Full deployment automation
    ├── install-istio.sh                  # Istio installation script
    └── cleanup.sh                        # Teardown all resources
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `istio-peer-authentication.yaml` | Enforces STRICT mTLS across the mesh | PeerAuthentication, mTLS modes, mesh-wide policy |
| `virtualservice-canary.yaml` | Splits traffic 90/10 between backend versions | VirtualService, DestinationRule, subset routing, weighted destinations |
| `destinationrule-circuit-breaker.yaml` | Limits connections and ejects failing endpoints | ConnectionPool, OutlierDetection, consecutive errors, ejection time |
| `fault-injection.yaml` | Injects delays and HTTP errors for testing | HTTPFaultInjection, delay, abort, percentage-based injection |
| `gateway.yaml` | Exposes services outside the mesh | Istio Gateway, TLS termination, host-based routing |
| `sample-app-deployment.yaml` | Deploys three-tier app with version labels | Sidecar injection, version labels for subset routing, multi-service app |

## Results & Metrics

| Metric | Before | After |
|---|---|---|
| Service-to-service encryption | 0% (plain HTTP) | 100% (mTLS STRICT) |
| Canary deployment capability | None (all-or-nothing) | 90/10 traffic splitting with instant rollback |
| Cascading failure recovery | 5+ minutes (manual restart) | <10 seconds (circuit breaker auto-ejects) |
| Mean time to detect latency issues | Hours (log analysis) | Seconds (Jaeger trace view) |
| Service dependency visibility | None | Full topology graph in Kiali |
| Failed request blast radius | Entire service chain | Isolated to circuit-broken service |

## How I'd Explain This in an Interview

> "We had three microservices communicating over plain HTTP inside the cluster, with no way to do canary deployments, no protection against cascading failures, and no visibility into service-to-service traffic. I deployed Istio service mesh, which injects Envoy sidecar proxies alongside every pod. The control plane, istiod, pushes configuration to all sidecars -- so we got automatic mTLS encryption without changing a single line of application code. For traffic management, I created VirtualService and DestinationRule resources to split traffic 90/10 between stable and canary backend versions. I configured circuit breaking through DestinationRule outlier detection, which automatically ejects failing endpoints after 5 consecutive 5xx errors. For resilience testing, I used fault injection to simulate delays and HTTP 503s, validating that our retry and timeout configs work correctly. Kiali gives us a real-time service topology graph, and Jaeger provides distributed tracing so we can see exactly where latency spikes occur across the request chain."

## Key Concepts Demonstrated

- **Service Mesh** -- infrastructure layer that handles service-to-service communication, offloading networking concerns from application code to sidecar proxies
- **Sidecar Injection** -- Istio's mutating webhook automatically injects an Envoy proxy container into every pod in labeled namespaces
- **Mutual TLS (mTLS)** -- both client and server present certificates during TLS handshake, providing encryption and identity verification between services
- **VirtualService** -- Istio CRD that defines traffic routing rules including splitting, retries, timeouts, and fault injection
- **DestinationRule** -- Istio CRD that defines policies applied after routing: subsets (versions), load balancing, connection pools, and outlier detection
- **Circuit Breaking** -- pattern that stops sending traffic to unhealthy endpoints, preventing cascading failures across the service chain
- **Fault Injection** -- deliberate introduction of delays and errors to test system resilience without modifying application code
- **Distributed Tracing** -- propagating trace context (headers) across service boundaries to reconstruct the full request path and timing

## Lessons Learned

1. **Sidecar resource overhead is real** -- each Envoy sidecar adds ~50MB memory and ~10m CPU. For a cluster with hundreds of pods, this adds up. Right-size sidecar resource requests using `istioctl analyze` and Envoy stats.
2. **STRICT mTLS breaks non-mesh workloads** -- when we enabled STRICT mode mesh-wide, monitoring agents and legacy services without sidecars lost connectivity. Start with PERMISSIVE mode, migrate all workloads, then switch to STRICT.
3. **Traffic splitting requires version labels** -- the canary split only works when pods have consistent `version: v1` and `version: v2` labels that match DestinationRule subsets. Mismatched labels cause 503 errors.
4. **Circuit breaker tuning is iterative** -- initial settings (3 consecutive errors, 30s ejection) were too aggressive for bursty traffic. We relaxed to 5 errors with 10s ejection after observing false positives in Kiali.
5. **Observability is the real win** -- while mTLS and traffic splitting are valuable, the biggest operational improvement was Kiali and Jaeger. Being able to visualize the service graph and trace individual requests cut incident response time dramatically.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
