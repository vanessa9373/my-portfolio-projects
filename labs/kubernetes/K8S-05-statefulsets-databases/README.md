# K8S-05: StatefulSets & Databases on Kubernetes

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white)
![StatefulSets](https://img.shields.io/badge/StatefulSets-Stable_Identities-blue?style=for-the-badge)

## Summary (The "Elevator Pitch")

StatefulSets solve the fundamental problem of running stateful workloads like databases in Kubernetes by providing stable network identities, persistent storage per replica, and ordered lifecycle management. This lab deploys PostgreSQL and MongoDB clusters using StatefulSets with headless services, volumeClaimTemplates, and replication -- proving that production databases can run reliably on Kubernetes when you use the right controller.

## The Problem

The team needs to run PostgreSQL and MongoDB clusters inside Kubernetes, but standard Deployments fall short for stateful workloads. Deployments assign random pod names on each restart (breaking database replication that depends on stable hostnames), provide no guarantee of ordered startup (a replica might try to join a primary that does not exist yet), and share storage rather than giving each replica its own persistent volume. Without stable identities and per-pod storage, clustered databases cannot function -- replicas cannot discover each other, data is lost on pod rescheduling, and failover is unpredictable. The team has been running databases on dedicated VMs outside the cluster, creating operational overhead with two separate infrastructure planes to manage.

## The Solution

We deploy StatefulSets that provide three critical guarantees for database workloads: stable network identities (pods are named `postgres-0`, `postgres-1`, `postgres-2` and retain those names across restarts), per-pod persistent storage via `volumeClaimTemplates` (each pod gets its own PVC that survives pod deletion), and ordered startup/shutdown via `OrderedReady` pod management policy. A headless Service gives each pod a predictable DNS record (`postgres-0.postgres-headless.default.svc.cluster.local`), enabling database replicas to discover and connect to each other. We demonstrate this with both PostgreSQL streaming replication and a MongoDB ReplicaSet, including failover testing.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                       │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Headless Service (clusterIP: None)            │  │
│  │          postgres-headless.default.svc.cluster.local       │  │
│  └──────────┬──────────────────┬──────────────────┬──────────┘  │
│             │                  │                  │              │
│    ┌────────▼───────┐ ┌───────▼────────┐ ┌───────▼────────┐    │
│    │  postgres-0    │ │  postgres-1    │ │  postgres-2    │    │
│    │  (Primary)     │ │  (Replica)     │ │  (Replica)     │    │
│    │                │ │                │ │                │    │
│    │  Port: 5432    │ │  Port: 5432    │ │  Port: 5432    │    │
│    └────────┬───────┘ └───────┬────────┘ └───────┬────────┘    │
│             │                  │                  │              │
│    ┌────────▼───────┐ ┌───────▼────────┐ ┌───────▼────────┐    │
│    │  PVC           │ │  PVC           │ │  PVC           │    │
│    │  data-pg-0     │ │  data-pg-1     │ │  data-pg-2     │    │
│    │  10Gi          │ │  10Gi          │ │  10Gi          │    │
│    └────────────────┘ └────────────────┘ └────────────────┘    │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              Headless Service (clusterIP: None)            │  │
│  │           mongo-headless.default.svc.cluster.local         │  │
│  └──────────┬──────────────────┬──────────────────┬──────────┘  │
│             │                  │                  │              │
│    ┌────────▼───────┐ ┌───────▼────────┐ ┌───────▼────────┐    │
│    │  mongo-0       │ │  mongo-1       │ │  mongo-2       │    │
│    │  (Primary)     │ │  (Secondary)   │ │  (Secondary)   │    │
│    └────────┬───────┘ └───────┬────────┘ └───────┬────────┘    │
│    ┌────────▼───────┐ ┌───────▼────────┐ ┌───────▼────────┐    │
│    │  PVC           │ │  PVC           │ │  PVC           │    │
│    │  data-mongo-0  │ │  data-mongo-1  │ │  data-mongo-2  │    │
│    └────────────────┘ └────────────────┘ └────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| Kubernetes StatefulSet | Controller for stateful pods | Provides stable identities, ordered deployment, and per-pod storage |
| Headless Service | DNS-based pod discovery | Gives each pod a predictable DNS name without load balancing |
| PostgreSQL 16 | Relational database | Industry standard RDBMS with mature streaming replication |
| MongoDB 7 | Document database | Native ReplicaSet support demonstrates StatefulSet patterns |
| volumeClaimTemplates | Per-pod persistent storage | Automatically provisions a unique PVC for each StatefulSet replica |
| ConfigMap | Database configuration | Externalizes pg_hba.conf and postgresql.conf from the image |
| kubectl | Cluster interaction | Standard Kubernetes CLI for deployment and verification |

## Implementation Steps

### Step 1: Create the Headless Service for PostgreSQL

```bash
kubectl apply -f manifests/headless-service.yaml
kubectl get svc postgres-headless
```

**What this does:** Creates a headless Service (clusterIP: None) that registers DNS A records for each pod in the StatefulSet. Instead of a single virtual IP, DNS queries return the individual pod IPs. This allows replicas to discover each other via `postgres-0.postgres-headless.default.svc.cluster.local`.

### Step 2: Deploy PostgreSQL StatefulSet with 3 Replicas

```bash
kubectl apply -f manifests/postgres-configmap.yaml
kubectl apply -f manifests/postgres-statefulset.yaml
kubectl get pods -l app=postgres -w
```

**What this does:** Deploys a 3-replica PostgreSQL StatefulSet with `volumeClaimTemplates` that automatically create a 10Gi PVC per pod. The ConfigMap injects PostgreSQL configuration for streaming replication. Pods are created in order: postgres-0 first, then postgres-1, then postgres-2 -- each waits for the previous to be Running and Ready.

### Step 3: Verify Stable Pod Identities and DNS

```bash
# Check pod names are stable and predictable
kubectl get pods -l app=postgres -o wide

# Verify DNS records for each pod
kubectl run dns-test --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup postgres-0.postgres-headless.default.svc.cluster.local

# Confirm each pod has its own PVC
kubectl get pvc -l app=postgres
```

**What this does:** Validates the three core StatefulSet guarantees -- pods have predictable names (postgres-0, postgres-1, postgres-2), each pod has a resolvable DNS hostname through the headless service, and each pod has its own dedicated PVC that persists independently.

### Step 4: Test Ordered Startup and Shutdown

```bash
# Delete a pod and watch it come back with the same name and PVC
kubectl delete pod postgres-1
kubectl get pods -l app=postgres -w

# Scale down -- pods terminate in reverse order (2, then 1)
kubectl scale statefulset postgres --replicas=1
kubectl get pods -l app=postgres -w

# Scale back up -- pods start in order (1, then 2)
kubectl scale statefulset postgres --replicas=3
```

**What this does:** Demonstrates OrderedReady pod management policy. When postgres-1 is deleted, it restarts with the same name and reattaches to the same PVC. Scaling down removes pods in reverse ordinal order. Scaling up creates them in forward order, waiting for each to be Ready.

### Step 5: Deploy MongoDB ReplicaSet as StatefulSet

```bash
kubectl apply -f manifests/mongo-headless-service.yaml
kubectl apply -f manifests/mongo-statefulset.yaml
kubectl get pods -l app=mongo -w
```

**What this does:** Deploys a 3-member MongoDB ReplicaSet using a StatefulSet. MongoDB's ReplicaSet protocol requires stable hostnames to track members, making StatefulSets the correct choice. Each mongo pod gets its own PVC for data directory persistence.

### Step 6: Configure Replication Between Pods

```bash
# Initialize the MongoDB ReplicaSet from mongo-0
kubectl exec mongo-0 -- mongosh --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo-0.mongo-headless.default.svc.cluster.local:27017" },
    { _id: 1, host: "mongo-1.mongo-headless.default.svc.cluster.local:27017" },
    { _id: 2, host: "mongo-2.mongo-headless.default.svc.cluster.local:27017" }
  ]
})'

# Verify replication status
kubectl exec mongo-0 -- mongosh --eval 'rs.status()'
```

**What this does:** Initializes MongoDB replication using the stable DNS names provided by the headless service. Each member is addressed by its StatefulSet-assigned hostname, ensuring the ReplicaSet configuration survives pod restarts.

### Step 7: Test Data Persistence and Failover

```bash
# Run the full failover test suite
chmod +x scripts/test-failover.sh
./scripts/test-failover.sh
```

**What this does:** Writes data to the primary, verifies replication to secondaries, kills the primary pod, confirms automatic failover election, and validates that data is still accessible from the new primary -- proving the full lifecycle of stateful failover on Kubernetes.

## Project Structure

```
K8S-05-statefulsets-databases/
├── README.md
├── manifests/
│   ├── headless-service.yaml          # Headless svc for PostgreSQL pod DNS
│   ├── postgres-statefulset.yaml      # PostgreSQL 3-replica StatefulSet
│   ├── postgres-configmap.yaml        # PostgreSQL configuration files
│   ├── mongo-headless-service.yaml    # Headless svc for MongoDB pod DNS
│   └── mongo-statefulset.yaml         # MongoDB 3-replica StatefulSet
└── scripts/
    ├── deploy.sh                      # Deploy all resources in order
    ├── test-failover.sh               # Automated failover testing
    └── cleanup.sh                     # Tear down all resources
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `headless-service.yaml` | Creates Service with `clusterIP: None` for PostgreSQL | Headless services, DNS-based discovery, no load balancer VIP |
| `postgres-statefulset.yaml` | Deploys 3 PostgreSQL pods with per-pod PVCs | `volumeClaimTemplates`, `podManagementPolicy`, `serviceName` |
| `postgres-configmap.yaml` | Injects pg_hba.conf and postgresql.conf | ConfigMap volume mounts, database configuration externalization |
| `mongo-statefulset.yaml` | Deploys 3 MongoDB pods for ReplicaSet | Anti-affinity for spread, command-based RS initialization |
| `mongo-headless-service.yaml` | Creates headless Service for MongoDB DNS | Same headless pattern, different database engine |
| `test-failover.sh` | Automates write, kill primary, verify failover | End-to-end validation of StatefulSet recovery guarantees |

## Results & Metrics

| Metric | Before (Deployments) | After (StatefulSets) |
|---|---|---|
| Pod identity stability | Random names on restart | Stable ordinal names (pod-0, pod-1, pod-2) |
| Storage persistence | Shared PVC, data loss on reschedule | Per-pod PVC, data survives pod deletion |
| Startup ordering | All pods start simultaneously | Ordered: 0 → 1 → 2 with readiness gates |
| DNS discoverability | Only service VIP | Per-pod DNS via headless service |
| Failover recovery time | Manual intervention (30+ min) | Automatic re-election (~10-15 seconds) |
| Replication configuration | Breaks on pod restart | Stable hostnames survive restarts |
| Operational overhead | Separate VM fleet for databases | Single Kubernetes control plane |

## How I'd Explain This in an Interview

> "We needed to run clustered databases in Kubernetes, but Deployments don't work for stateful workloads because pods get random names and share storage. I used StatefulSets which give each pod a stable identity -- postgres-0 is always postgres-0, even after a restart -- and volumeClaimTemplates that automatically create a dedicated PVC per replica. Combined with a headless Service, each pod gets a predictable DNS name like postgres-0.postgres-headless, which is exactly what database replication protocols need to track cluster members. I demonstrated this with both PostgreSQL streaming replication and a MongoDB ReplicaSet, including automated failover testing that proves data survives primary pod failure."

## Key Concepts Demonstrated

- **StatefulSet** -- Kubernetes controller that manages stateful applications with stable network identities, ordered deployment, and per-pod persistent storage
- **Headless Service** -- A Service with `clusterIP: None` that creates individual DNS A records for each backing pod instead of a single virtual IP
- **volumeClaimTemplates** -- StatefulSet-specific field that automatically creates a unique PersistentVolumeClaim for each pod replica
- **Stable Network Identity** -- Pods are named with a predictable ordinal index (pod-0, pod-1) and retain that name across restarts
- **OrderedReady Pod Management** -- Pods are created sequentially (0 before 1 before 2) and terminated in reverse order
- **Parallel Pod Management** -- Alternative policy where all pods start/stop simultaneously, used when ordering is unnecessary
- **Persistent Volume Claim (PVC)** -- Storage request that binds to a PersistentVolume, ensuring data outlives the pod lifecycle
- **Database Replication** -- Process of copying data from a primary instance to replicas for high availability and read scaling

## Lessons Learned

1. **Headless services are the glue** -- Without `clusterIP: None`, pods cannot discover each other by name. The headless service is what makes StatefulSet DNS work, and forgetting it is the most common StatefulSet mistake.
2. **PVCs outlive StatefulSets on purpose** -- When you delete a StatefulSet, the PVCs remain. This is a safety feature to prevent data loss, but it means you must clean up PVCs manually or they consume storage indefinitely.
3. **OrderedReady has real performance implications** -- Sequential startup means a 10-replica StatefulSet takes 10x longer to deploy than a Deployment. For databases this is correct, but for stateful apps that do not need ordering, use `Parallel` pod management.
4. **Pod anti-affinity is critical for real HA** -- StatefulSets alone do not prevent all replicas from landing on the same node. You must add pod anti-affinity rules to spread database pods across failure domains.
5. **Init containers solve the bootstrap problem** -- The primary pod (ordinal 0) needs different configuration than replicas. Using init containers that check the pod's ordinal to branch logic is the standard pattern for database StatefulSet initialization.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
