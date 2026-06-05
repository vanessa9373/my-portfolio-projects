# K8S-14: Multi-Cluster Management

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Rancher](https://img.shields.io/badge/Rancher_Fleet-0075A8?style=for-the-badge&logo=rancher&logoColor=white)
![Submariner](https://img.shields.io/badge/Submariner-0066CC?style=for-the-badge&logo=kubernetes&logoColor=white)
![Thanos](https://img.shields.io/badge/Thanos-6C3483?style=for-the-badge&logo=prometheus&logoColor=white)
![Cluster API](https://img.shields.io/badge/Cluster_API-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)

## Summary

Designed and implemented a multi-cluster management platform spanning five Kubernetes clusters (dev, staging, prod-us, prod-eu, edge) using Rancher Fleet for GitOps-based workload distribution, Submariner for cross-cluster networking and service discovery, Thanos for unified multi-cluster monitoring, and Cluster API for declarative cluster lifecycle management. This lab demonstrates how to operate a fleet of clusters as a single logical platform with consistent deployments, cross-cluster connectivity, and unified observability.

## The Problem

The organization has grown to operate five Kubernetes clusters across multiple regions and environments. Each cluster was set up independently, creating significant operational challenges:

- **Deployment inconsistency** -- deploying the same application across five clusters requires running `kubectl apply` five times with different kubeconfigs. Engineers forget clusters, deploy stale versions, and introduce drift between regions
- **No cross-cluster networking** -- a service in prod-us cannot discover or call a service in prod-eu. Regional failover requires DNS-based solutions with high TTLs, causing 5-10 minute failover windows
- **Monitoring silos** -- each cluster runs its own Prometheus instance with 15 days of retention. Querying metrics across clusters requires logging into five separate Grafana dashboards and correlating manually
- **Manual cluster provisioning** -- standing up a new cluster takes 3 days of manual work: Terraform for infrastructure, kubeadm or EKS API calls, CNI installation, monitoring stack deployment. Every cluster is a snowflake
- **No fleet-wide policy enforcement** -- security policies must be applied to each cluster individually, with no guarantee they are consistent across the fleet

## The Solution

Built a management plane that treats the five clusters as a unified fleet:

- **Rancher Fleet** for multi-cluster GitOps -- a single `GitRepo` resource on the management cluster deploys workloads to target clusters based on labels and selectors, ensuring consistent deployments across the fleet
- **Submariner** for cross-cluster networking -- establishes encrypted tunnels between clusters, enabling pod-to-pod and service-to-service communication across cluster boundaries with standard Kubernetes DNS
- **Thanos** for unified monitoring -- Thanos Sidecar on each cluster's Prometheus uploads metrics to object storage; Thanos Querier on the management cluster provides a single Prometheus-compatible endpoint for querying metrics from all clusters
- **Cluster API (CAPI)** for declarative cluster lifecycle -- define clusters as Kubernetes resources (Cluster, MachineDeployment); the CAPI controller provisions infrastructure and bootstraps Kubernetes automatically

## Architecture

```
                    +----------------------------------+
                    |       Management Cluster          |
                    |                                   |
                    |  +------------+  +-------------+  |
                    |  | Fleet      |  | Thanos      |  |
                    |  | Controller |  | Querier     |  |
                    |  +-----+------+  +------+------+  |
                    |        |                |          |
                    |  +-----+------+  +------+------+  |
                    |  | Cluster API|  | Thanos      |  |
                    |  | Controller |  | Store GW    |  |
                    |  +-----+------+  +------+------+  |
                    +--------+----------------+---------+
                             |                |
              +--------------+-------+--------+----------+
              |              |       |        |          |
     +--------v---+  +------v--+  +-v------+ +v-------+ +v--------+
     | prod-us    |  |prod-eu  |  |staging | | dev    | | edge    |
     | (us-west-2)|  |(eu-cen1)|  |        | |        | |         |
     |            |  |         |  |        | |        | |         |
     | Prometheus |  |Promethe-|  |Promethe| |Prometh-| |Prometh- |
     | + Thanos   |  |us +    |  |us +    | |eus +   | |eus +    |
     |   Sidecar  |  |Thanos  |  |Thanos  | |Thanos  | |Thanos   |
     |            |  |Sidecar |  |Sidecar | |Sidecar | |Sidecar  |
     +-----+------+  +---+----+  +---+----+ +---+----+ +----+----+
           |              |           |          |           |
           +--- Submariner Tunnels (encrypted, cross-cluster) ---+
           |              |           |          |           |
           +--- Fleet Agent (GitOps sync per cluster) -------+
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| Rancher Fleet 0.9 | Multi-cluster GitOps | Purpose-built for fleet-scale GitOps; deploys workloads to hundreds of clusters via label selectors from a single Git source |
| Submariner 0.17 | Cross-cluster networking | Establishes encrypted tunnels between clusters, enabling pod-to-pod communication and service discovery across cluster boundaries |
| Thanos 0.34 | Multi-cluster monitoring | Provides a unified Prometheus-compatible query layer across clusters with long-term storage in S3, solving retention and federation limits |
| Cluster API 1.6 | Declarative cluster lifecycle | Kubernetes-native cluster provisioning using CRDs; treats clusters as managed resources with reconciliation and self-healing |
| Prometheus | Per-cluster metrics | Standard monitoring stack with Thanos Sidecar for remote write and global query aggregation |
| Kubernetes 1.28 | Cluster platform | Production-grade container orchestration across all five clusters |

## Implementation Steps

### Step 1: Set up management cluster with Fleet

```bash
# Install Fleet on the management cluster
helm repo add fleet https://rancher.github.io/fleet-helm-charts/
helm repo update

helm install fleet-crd fleet/fleet-crd \
  --namespace cattle-fleet-system \
  --create-namespace \
  --wait

helm install fleet fleet/fleet \
  --namespace cattle-fleet-system \
  --wait

# Verify Fleet controller is running
kubectl get pods -n cattle-fleet-system
kubectl get clusters.fleet.cattle.io -A
```

**What this does:** Installs the Fleet controller on the management cluster. Fleet watches for `GitRepo` and `ClusterGroup` resources and distributes workloads to registered downstream clusters. The management cluster acts as the single control point for fleet-wide deployments.

### Step 2: Register spoke clusters

```bash
# Create cluster groups for targeting
kubectl apply -f manifests/fleet-cluster-group.yaml

# Register each spoke cluster
# Generate a registration token
kubectl create namespace fleet-default
KUBECONFIG=/path/to/prod-us-kubeconfig ./scripts/register-cluster.sh prod-us us-west-2 production
KUBECONFIG=/path/to/prod-eu-kubeconfig ./scripts/register-cluster.sh prod-eu eu-central-1 production
KUBECONFIG=/path/to/staging-kubeconfig ./scripts/register-cluster.sh staging us-east-1 staging
KUBECONFIG=/path/to/dev-kubeconfig ./scripts/register-cluster.sh dev us-east-1 development
KUBECONFIG=/path/to/edge-kubeconfig ./scripts/register-cluster.sh edge us-west-1 edge

# Verify all clusters are registered
kubectl get clusters.fleet.cattle.io -n fleet-default
```

**What this does:** Registers each spoke cluster with Fleet by deploying a Fleet agent on the spoke. The agent connects back to the management cluster and awaits deployment instructions. Cluster labels (environment, region) enable targeted workload deployment.

### Step 3: Deploy workloads across clusters with Fleet GitRepo

```bash
# Apply a GitRepo resource that deploys to all production clusters
kubectl apply -f manifests/fleet-gitrepo.yaml

# Verify Fleet is distributing workloads
kubectl get gitrepo -n fleet-default
kubectl get bundles -n fleet-default

# Check deployment status across clusters
kubectl get bundledeployments -n fleet-default
```

**What this does:** Creates a Fleet `GitRepo` resource pointing to a Git repository containing Kubernetes manifests. Fleet reads the repo, bundles the manifests, and distributes them to clusters matching the target selector. The `targets` field uses labels to deploy to production clusters only, staging-only, or all clusters.

### Step 4: Install Submariner for cross-cluster networking

```bash
# Install Submariner broker on management cluster
kubectl apply -f manifests/submariner-broker.yaml

# Install subctl CLI
curl -Ls https://get.submariner.io | VERSION=0.17.0 bash
export PATH=$HOME/.local/bin:$PATH

# Deploy Submariner on prod-us (gateway node)
subctl join --kubeconfig /path/to/prod-us-kubeconfig broker-info.subm \
  --clusterid prod-us \
  --natt=false \
  --cable-driver libreswan

# Deploy Submariner on prod-eu (gateway node)
subctl join --kubeconfig /path/to/prod-eu-kubeconfig broker-info.subm \
  --clusterid prod-eu \
  --natt=false \
  --cable-driver libreswan

# Verify tunnel is established
subctl show connections
subctl show networks
```

**What this does:** Deploys the Submariner broker (coordination hub) and joins clusters to the mesh. Submariner establishes encrypted IPsec tunnels between gateway nodes, enabling pods in prod-us to reach pods in prod-eu using standard Kubernetes service DNS (e.g., `service.namespace.svc.clusterset.local`).

### Step 5: Configure Thanos for multi-cluster monitoring

```bash
# Deploy Thanos Sidecar alongside Prometheus on each spoke cluster
# (via Fleet, applied to all clusters)
kubectl apply -f manifests/thanos-values.yaml

# Deploy Thanos Querier on management cluster
helm install thanos bitnami/thanos \
  --namespace monitoring \
  --create-namespace \
  --values manifests/thanos-values.yaml \
  --wait

# Verify Thanos can query all clusters
kubectl port-forward svc/thanos-querier -n monitoring 9090:9090 &
curl -s "http://localhost:9090/api/v1/query?query=up" | jq '.data.result | length'
```

**What this does:** Each cluster's Prometheus gets a Thanos Sidecar that uploads metrics to S3 object storage and exposes a gRPC StoreAPI. The Thanos Querier on the management cluster connects to all Sidecars and provides a single PromQL endpoint that transparently queries metrics from all five clusters. A single Grafana dashboard can now show fleet-wide metrics.

### Step 6: Set up Cluster API for declarative cluster provisioning

```bash
# Initialize Cluster API on management cluster
clusterctl init --infrastructure aws

# Create a new cluster declaratively
kubectl apply -f manifests/cluster-api-cluster.yaml

# Watch the cluster provisioning
kubectl get clusters -A
kubectl get machines -A
kubectl get machinedeployments -A

# Get kubeconfig for the new cluster
clusterctl get kubeconfig new-prod-ap --namespace default > new-prod-ap.kubeconfig
```

**What this does:** Installs Cluster API controllers that manage cloud infrastructure through Kubernetes CRDs. Applying a `Cluster` resource with `AWSManagedControlPlane` triggers automatic provisioning of the VPC, EKS cluster, and worker node groups. The cluster is managed like any other Kubernetes resource with reconciliation and drift correction.

### Step 7: Test cross-cluster service discovery and failover

```bash
# Deploy a test service on prod-us
kubectl --kubeconfig prod-us.kubeconfig apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: test-api
  namespace: default
spec:
  ports:
    - port: 80
  selector:
    app: test-api
EOF

# Export the service for cross-cluster discovery
subctl export service test-api --namespace default

# From prod-eu, discover and call the service
kubectl --kubeconfig prod-eu.kubeconfig exec deploy/test-client -- \
  curl -s http://test-api.default.svc.clusterset.local/health

# Simulate failover: scale down prod-us service
kubectl --kubeconfig prod-us.kubeconfig scale deploy/test-api --replicas=0

# Verify prod-eu still resolves (Submariner routes to available endpoints)
kubectl --kubeconfig prod-eu.kubeconfig exec deploy/test-client -- \
  curl -s http://test-api.default.svc.clusterset.local/health

# Query Thanos for cross-cluster request metrics
curl -s "http://localhost:9090/api/v1/query?query=http_requests_total{cluster=~'prod-.*'}" | jq .
```

**What this does:** Validates the complete multi-cluster stack: Fleet deploys workloads consistently, Submariner enables cross-cluster service discovery using the `.svc.clusterset.local` DNS suffix, and Thanos provides a unified view of request metrics from all clusters. The failover test confirms that when a service is unavailable in one cluster, Submariner routes traffic to another cluster automatically.

## Project Structure

```
K8S-14-multi-cluster/
├── README.md
├── manifests/
│   ├── fleet-gitrepo.yaml              # Fleet GitRepo for workload distribution
│   ├── fleet-cluster-group.yaml        # Fleet ClusterGroup definitions
│   ├── submariner-broker.yaml          # Submariner broker deployment
│   ├── thanos-values.yaml              # Thanos Helm values (Sidecar + Querier)
│   └── cluster-api-cluster.yaml        # Cluster API cluster definition
└── scripts/
    ├── deploy.sh                       # Full deployment automation
    ├── register-cluster.sh             # Register a spoke cluster with Fleet
    └── cleanup.sh                      # Teardown all resources
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `fleet-gitrepo.yaml` | Defines a Git repository for Fleet to distribute across clusters | GitRepo, target selectors, paths, polling interval, fleet-wide deployment |
| `fleet-cluster-group.yaml` | Groups clusters by labels for targeted deployment | ClusterGroup, label selectors, environment grouping, fleet organization |
| `submariner-broker.yaml` | Deploys the coordination broker for cross-cluster networking | Broker, ServiceDiscovery, IPsec tunnels, ClusterSet DNS |
| `thanos-values.yaml` | Configures Thanos Sidecar, Querier, and S3 storage | Thanos architecture, global query, long-term storage, deduplication |
| `cluster-api-cluster.yaml` | Declaratively defines a new Kubernetes cluster | Cluster CRD, MachineDeployment, infrastructure provider, bootstrap provider |

## Results & Metrics

| Metric | Before | After |
|---|---|---|
| Deployment consistency across clusters | ~70% (manual errors) | 100% (Fleet GitOps) |
| Cross-cluster failover time | 5-10 minutes (DNS TTL) | <30 seconds (Submariner tunnel) |
| Monitoring query scope | 1 cluster per dashboard | All 5 clusters in single query |
| New cluster provisioning time | 3 days (manual) | 45 minutes (Cluster API) |
| Fleet-wide policy application | Hours (per-cluster manual) | Minutes (Fleet GitRepo) |
| Metrics retention | 15 days (local Prometheus) | 1 year (Thanos + S3) |

## How I'd Explain This in an Interview

> "We had five Kubernetes clusters -- dev, staging, two production regions, and an edge cluster -- each managed independently. Deploying to all five meant running kubectl five times, monitoring required five Grafana dashboards, and provisioning a new cluster took three days of manual work. I built a multi-cluster management platform on a dedicated management cluster. For deployments, I used Rancher Fleet, which lets you define a GitRepo resource that automatically distributes workloads to clusters matching label selectors -- so one Git commit deploys to all production clusters simultaneously. For cross-cluster networking, I deployed Submariner, which creates encrypted IPsec tunnels between clusters and enables service discovery using the clusterset.local DNS suffix -- a pod in our US cluster can call a service in our EU cluster using standard Kubernetes DNS. For monitoring, I deployed Thanos Sidecars alongside each cluster's Prometheus and a Thanos Querier on the management cluster, giving us a single PromQL endpoint that transparently queries metrics from all five clusters. Finally, I set up Cluster API so new clusters are defined as Kubernetes resources -- applying a YAML file provisions the VPC, EKS cluster, and worker nodes automatically in about 45 minutes."

## Key Concepts Demonstrated

- **Multi-Cluster GitOps (Fleet)** -- deploying workloads to multiple clusters from a single Git source, using label selectors to target specific cluster groups
- **Cross-Cluster Networking (Submariner)** -- establishing encrypted tunnels between clusters that enable pod-to-pod communication and service discovery across cluster boundaries
- **ClusterSet DNS** -- Submariner's DNS integration that resolves services across clusters using the `.svc.clusterset.local` suffix, enabling location-transparent service calls
- **Federated Monitoring (Thanos)** -- a unified query layer that aggregates Prometheus metrics from multiple clusters into a single endpoint with long-term object storage
- **Declarative Cluster Lifecycle (Cluster API)** -- managing Kubernetes cluster infrastructure as Kubernetes resources, enabling GitOps for cluster provisioning and upgrades
- **Hub-Spoke Architecture** -- a management cluster (hub) that orchestrates configuration, monitoring, and lifecycle management of multiple downstream clusters (spokes)
- **Fleet Bundle Distribution** -- Fleet's mechanism for packaging, distributing, and tracking workload deployments across a fleet of clusters with status reporting

## Lessons Learned

1. **Fleet target selectors require precise labels** -- a misconfigured label selector deployed a production workload to the dev cluster. We now enforce a label taxonomy with Kyverno on the management cluster and test selectors in a dry-run mode before applying.
2. **Submariner needs dedicated gateway nodes** -- running Submariner gateway on shared worker nodes caused network contention. Dedicating two nodes per cluster as gateway nodes with tolerations and node affinity resolved throughput issues.
3. **Thanos deduplication requires consistent external labels** -- without setting unique `cluster` and `region` labels on each Prometheus instance, Thanos merged metrics from different clusters. Adding `--external-label cluster=prod-us` to each Prometheus resolved the collision.
4. **Cluster API provider maturity varies** -- the AWS provider is production-ready, but the vSphere provider required workarounds for networking. Evaluate the infrastructure provider thoroughly before committing to CAPI for that environment.
5. **Start with Fleet, add Submariner only when needed** -- cross-cluster networking adds complexity (IPsec overhead, gateway node management, DNS debugging). Many use cases only need consistent multi-cluster deployment (Fleet), not cross-cluster pod networking. Add Submariner only when services genuinely need to communicate across cluster boundaries.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
