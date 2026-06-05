# Lab K8S-04: Jobs, CronJobs & Init Containers

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![CronJob](https://img.shields.io/badge/CronJobs-326CE5?style=flat&logo=kubernetes&logoColor=white)
![YAML](https://img.shields.io/badge/YAML-CB171E?style=flat&logo=yaml&logoColor=white)

## Summary (The "Elevator Pitch")

Replaced ad-hoc SSH cron jobs and manual batch scripts with Kubernetes-native Jobs, CronJobs, and Init Containers. Batch workloads now have automatic retry logic, configurable parallelism, failure visibility, and dependency management -- all declarative and version-controlled. Database migrations, report generation, and cleanup tasks run reliably without human intervention.

## The Problem

Batch operations -- database migrations, nightly report generation, data cleanup, and log rotation -- were managed via **SSH cron on individual VMs**. There was no retry logic: if a migration script failed at 2 AM, no one knew until morning. Running jobs in parallel required manual orchestration across multiple VMs. There was **no visibility** into job history, no way to set deadlines, and no mechanism to check dependencies before running (e.g., "is the database ready?"). When the cron VM went down, all scheduled tasks stopped silently.

## The Solution

Implemented Kubernetes **Jobs** for one-off batch tasks with configurable retry logic (`backoffLimit`) and deadlines (`activeDeadlineSeconds`). **CronJobs** handle scheduled work (cleanup every 5 minutes, reports nightly) with concurrency policies and history limits. **Init Containers** ensure dependencies are met before the main container runs (wait for database readiness). **Sidecar Containers** handle cross-cutting concerns like log shipping. **Lifecycle hooks** enable graceful shutdown patterns. Everything is declarative, versioned, and observable.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Namespace: k8s-batch                              │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │                    CronJob (every 5 min)                 │        │
│  │  schedule: "*/5 * * * *"                                │        │
│  │  concurrencyPolicy: Forbid                               │        │
│  └──────────────────────┬──────────────────────────────────┘        │
│                         │ spawns                                     │
│                         ▼                                            │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │                       Job                                │        │
│  │  completions: 5  |  parallelism: 3  |  backoffLimit: 4  │        │
│  └──────────────────────┬──────────────────────────────────┘        │
│                         │ creates                                    │
│                         ▼                                            │
│  ┌─────────────────────────────────────────────────────────┐        │
│  │                       Pod                                │        │
│  │                                                          │        │
│  │  ┌──────────────┐    ┌──────────────┐    ┌───────────┐  │        │
│  │  │ Init Container│───►│ Main Container│───►│  Sidecar  │  │        │
│  │  │              │    │              │    │ Container │  │        │
│  │  │ wait-for-db  │    │ run-migration│    │ log-ship  │  │        │
│  │  │              │    │              │    │           │  │        │
│  │  │ Check DB is  │    │ Execute the  │    │ Stream    │  │        │
│  │  │ reachable    │    │ batch task   │    │ logs to   │  │        │
│  │  │ before main  │    │              │    │ central   │  │        │
│  │  │ starts       │    │ postStart:   │    │ logging   │  │        │
│  │  └──────────────┘    │  log start   │    └───────────┘  │        │
│  │                      │ preStop:     │                    │        │
│  │                      │  graceful    │                    │        │
│  │                      │  shutdown    │                    │        │
│  │                      └──────────────┘                    │        │
│  └─────────────────────────────────────────────────────────┘        │
│                                                                      │
│  Failure Handling:                                                   │
│  backoffLimit: 4 (retry up to 4 times with exponential backoff)     │
│  activeDeadlineSeconds: 600 (kill after 10 minutes)                 │
│  ttlSecondsAfterFinished: 3600 (cleanup completed jobs after 1 hr) │
└─────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| Kubernetes Jobs | One-off batch task execution with retry logic | Native K8s workload type for run-to-completion tasks |
| Kubernetes CronJobs | Scheduled task execution | Built-in cron scheduling without external cron daemon |
| Init Containers | Pre-flight dependency checks | Guaranteed to run before main container; blocks until successful |
| Sidecar Containers | Cross-cutting concerns (logging, monitoring) | Separation of concerns; main container stays focused |
| Lifecycle Hooks | Startup/shutdown actions (postStart, preStop) | Graceful shutdown, resource cleanup, notification |
| kubectl | Kubernetes CLI | Monitor job status, view logs, debug failures |
| Minikube/kind | Local Kubernetes cluster | Test batch workloads locally before production |

## Implementation Steps

### Step 1: Create a Simple Job (One-Off Task)
**What this does:** Creates a Job that runs a single batch task to completion. The Job creates a Pod, the Pod runs the command, and when it exits successfully (exit code 0), the Job is marked as completed. If it fails, Kubernetes retries up to `backoffLimit` times with exponential backoff.
```bash
kubectl create namespace k8s-batch
kubectl apply -f manifests/job-simple.yaml
kubectl get jobs -n k8s-batch
kubectl get pods -n k8s-batch -w
# Wait for completion
kubectl wait --for=condition=Complete job/db-migration -n k8s-batch --timeout=120s
# View job logs
kubectl logs job/db-migration -n k8s-batch
# Check job details
kubectl describe job db-migration -n k8s-batch
```

### Step 2: Create a Parallel Job (Completions + Parallelism)
**What this does:** Creates a Job that must complete 5 work items (`completions: 5`), running up to 3 at a time (`parallelism: 3`). Kubernetes creates pods in waves: first 3 pods run in parallel, as each completes a new one starts, until all 5 are done. This is how you process queues, generate reports in parallel, or run test suites.
```bash
kubectl apply -f manifests/job-parallel.yaml
kubectl get jobs -n k8s-batch -w
kubectl get pods -n k8s-batch -l job-name=report-generator -w
# Watch completions progress: 0/5 → 3/5 → 5/5
kubectl describe job report-generator -n k8s-batch
# View logs from all pods
kubectl logs -l job-name=report-generator -n k8s-batch --prefix
```

### Step 3: Create a CronJob (Scheduled Every 5 Minutes)
**What this does:** Creates a CronJob that spawns a new Job every 5 minutes. The `concurrencyPolicy: Forbid` ensures a new Job is not created if the previous one is still running. `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` control how many completed/failed Jobs are kept for debugging.
```bash
kubectl apply -f manifests/cronjob.yaml
kubectl get cronjobs -n k8s-batch
kubectl describe cronjob data-cleanup -n k8s-batch
# Wait for the first run (up to 5 minutes)
echo "Waiting for first CronJob execution..."
kubectl get jobs -n k8s-batch -w
# View the spawned jobs
kubectl get jobs -n k8s-batch -l app=data-cleanup
# Manually trigger a CronJob run
kubectl create job --from=cronjob/data-cleanup manual-cleanup-$(date +%s) -n k8s-batch
```

### Step 4: Add Init Container (Wait for Dependency)
**What this does:** Creates a Pod with an Init Container that checks if a database service is reachable before the main container starts. The Init Container loops, attempting to connect to the database. Only when it succeeds does the main container start. This prevents the main application from crashing on startup due to missing dependencies.
```bash
kubectl apply -f manifests/pod-init-container.yaml
kubectl get pods -n k8s-batch -w
# Watch the pod status: Init:0/1 → PodInitializing → Running
kubectl describe pod app-with-init -n k8s-batch
# View init container logs
kubectl logs app-with-init -n k8s-batch -c wait-for-db
# View main container logs
kubectl logs app-with-init -n k8s-batch -c app
```

### Step 5: Add Sidecar Container (Log Shipping)
**What this does:** Creates a Pod with a main container that writes logs to a shared volume, and a sidecar container that reads and ships those logs. The shared `emptyDir` volume enables inter-container communication. This pattern separates log shipping from application logic so you can swap log shippers without changing the app.
```bash
kubectl apply -f manifests/pod-sidecar.yaml
kubectl get pods -n k8s-batch -w
# View main container logs (writing)
kubectl logs app-with-sidecar -n k8s-batch -c app
# View sidecar container logs (shipping)
kubectl logs app-with-sidecar -n k8s-batch -c log-shipper
# Verify shared volume
kubectl exec app-with-sidecar -n k8s-batch -c app -- ls -la /var/log/app/
kubectl exec app-with-sidecar -n k8s-batch -c log-shipper -- ls -la /var/log/app/
```

### Step 6: Configure Lifecycle Hooks (preStop Graceful Shutdown)
**What this does:** Adds `postStart` and `preStop` lifecycle hooks to a Pod. The `postStart` hook runs immediately after the container starts (registration, warmup). The `preStop` hook runs before the container is terminated (drain connections, flush buffers, deregister). This gives the container time to shut down gracefully instead of being killed immediately.
```bash
kubectl apply -f manifests/pod-lifecycle.yaml
kubectl get pods -n k8s-batch -w
# View the postStart hook output
kubectl logs app-with-hooks -n k8s-batch
# Trigger preStop by deleting the pod
echo "Deleting pod to trigger preStop hook..."
kubectl delete pod app-with-hooks -n k8s-batch --grace-period=30
# The container gets 30 seconds to run preStop before SIGKILL
```

### Step 7: Test Failure Handling (backoffLimit, activeDeadlineSeconds)
**What this does:** Creates a Job that deliberately fails to demonstrate Kubernetes retry behavior. The Job retries with exponential backoff (10s, 20s, 40s, 80s) up to `backoffLimit` times. The `activeDeadlineSeconds` sets an absolute deadline -- if the Job has not completed by then, all pods are terminated. The `ttlSecondsAfterFinished` automatically cleans up completed Jobs.
```bash
# Deploy a job that will fail (exit code 1)
kubectl apply -f manifests/job-simple.yaml
# Watch retry behavior
kubectl get pods -n k8s-batch -l job-name=db-migration -w
# Check backoff timing in events
kubectl describe job db-migration -n k8s-batch
# View the failed pod logs
kubectl logs -l job-name=db-migration -n k8s-batch --prefix --all-containers
# Check job status (conditions: Complete or Failed)
kubectl get jobs -n k8s-batch -o wide
```

## Project Structure

```
K8S-04-jobs-cronjobs/
├── README.md                          # Lab documentation (this file)
├── manifests/
│   ├── job-simple.yaml                # One-off batch Job (DB migration)
│   ├── job-parallel.yaml              # Parallel Job (completions + parallelism)
│   ├── cronjob.yaml                   # CronJob (scheduled cleanup every 5 min)
│   ├── pod-init-container.yaml        # Pod with Init Container (wait for DB)
│   ├── pod-sidecar.yaml               # Pod with Sidecar (log shipping)
│   └── pod-lifecycle.yaml             # Pod with lifecycle hooks (postStart/preStop)
└── scripts/
    ├── deploy.sh                      # Apply all manifests in order
    └── cleanup.sh                     # Delete namespace (removes everything)
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `manifests/job-simple.yaml` | Runs a one-off database migration with retry logic and TTL cleanup | Jobs, backoffLimit, activeDeadlineSeconds, ttlSecondsAfterFinished |
| `manifests/job-parallel.yaml` | Generates 5 reports with up to 3 running concurrently | Parallel Jobs, completions, parallelism, work queue pattern |
| `manifests/cronjob.yaml` | Runs data cleanup every 5 minutes with concurrency control | CronJobs, schedule syntax, concurrencyPolicy, history limits |
| `manifests/pod-init-container.yaml` | Blocks main container until database is reachable | Init Containers, dependency ordering, service readiness |
| `manifests/pod-sidecar.yaml` | Ships application logs via a sidecar container using shared volume | Sidecar pattern, emptyDir shared volumes, separation of concerns |
| `manifests/pod-lifecycle.yaml` | Runs startup registration and graceful shutdown hooks | postStart, preStop, terminationGracePeriodSeconds |
| `scripts/deploy.sh` | Deploys all manifests and monitors job execution | Batch deployment automation |
| `scripts/cleanup.sh` | Deletes the k8s-batch namespace and all resources | Namespace-scoped cleanup |

## Results & Metrics

| Metric | Before (SSH Cron) | After (K8s Jobs/CronJobs) | Improvement |
|--------|-------------------|--------------------------|-------------|
| Failure Detection | Next morning (manual) | Immediate (events + alerts) | **Hours to seconds** |
| Retry Logic | None (manual re-run) | Automatic (exponential backoff) | **Self-healing batch** |
| Parallel Execution | Manual SSH to N VMs | `parallelism: N` in YAML | **One-line config** |
| Job History | Lost (no audit trail) | Kept (successfulJobsHistoryLimit) | **Full audit trail** |
| Dependency Checks | None (hope for the best) | Init Containers (guaranteed) | **Zero startup failures** |
| Scheduling | VM cron (single point of failure) | CronJob (cluster-wide, HA) | **No SPOF** |

## How I'd Explain This in an Interview

> "The team was running batch operations -- database migrations, report generation, data cleanup -- via SSH cron on individual VMs. If a job failed at 2 AM, nobody knew until morning. There was no retry logic, no parallelism, and no dependency checking. I migrated everything to Kubernetes Jobs and CronJobs. Jobs handle one-off tasks like database migrations with automatic retry (backoffLimit) and deadlines (activeDeadlineSeconds). CronJobs replaced VM cron for scheduled work with concurrency policies so we never have two cleanup jobs fighting each other. Init Containers solved the dependency problem: before a migration runs, an init container verifies the database is reachable. The biggest win was visibility -- every Job creates events, logs, and status conditions that feed into our alerting pipeline. Failed jobs trigger PagerDuty alerts instead of being discovered the next day."

## Key Concepts Demonstrated

- **Jobs** — Run-to-completion workloads that create pods, track completions, and retry on failure
- **Completions** — Number of pod completions required for a Job to be considered done
- **Parallelism** — Maximum number of pods running concurrently for a Job
- **backoffLimit** — Maximum retry attempts before marking a Job as failed (exponential backoff: 10s, 20s, 40s...)
- **activeDeadlineSeconds** — Absolute time limit for a Job; all pods terminated if exceeded
- **ttlSecondsAfterFinished** — Automatic cleanup of completed/failed Jobs after a time period
- **CronJobs** — Scheduled Jobs using cron syntax; spawns a new Job on each schedule tick
- **concurrencyPolicy** — Controls overlap: Allow (concurrent runs), Forbid (skip if running), Replace (kill and restart)
- **Init Containers** — Containers that run to completion before main containers start; used for dependency checks and setup
- **Sidecar Containers** — Long-running containers alongside the main container for cross-cutting concerns (logging, proxying)
- **Lifecycle Hooks** — postStart (runs after container start) and preStop (runs before container termination)
- **terminationGracePeriodSeconds** — Time allowed for preStop hook and SIGTERM handling before SIGKILL

## Lessons Learned

1. **Always set activeDeadlineSeconds on Jobs** — Without a deadline, a stuck Job runs forever, consuming resources. A 10-minute migration that takes 3 hours is broken; the deadline catches it and alerts you instead of silently burning CPU.
2. **Use concurrencyPolicy: Forbid for data-mutating CronJobs** — If a cleanup job takes longer than the schedule interval, the default `Allow` policy spawns a second instance. Two concurrent cleanups on the same data cause race conditions. `Forbid` skips the run if the previous one is still active.
3. **Init Containers are sequential, not parallel** — If you have three init containers, they run one at a time in order. Put the fastest check first (DNS resolution) and the slowest last (database schema validation) to fail fast.
4. **ttlSecondsAfterFinished prevents Job accumulation** — Without TTL, completed Jobs and their pods pile up forever. Set a reasonable TTL (1 hour for dev, 24 hours for production) so you have time to debug failures but do not accumulate garbage indefinitely.
5. **preStop hooks need terminationGracePeriodSeconds** — The preStop hook runs within the grace period. If your preStop takes 25 seconds and the grace period is 30 seconds, you have only 5 seconds for SIGTERM. Always set the grace period longer than your preStop needs.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
