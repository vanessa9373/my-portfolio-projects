# Kubernetes Mastery Lab Guide — Beginner to Expert

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)
![Istio](https://img.shields.io/badge/Istio-466BB0?style=flat&logo=istio&logoColor=white)

A comprehensive 18-lab learning path covering Kubernetes from first `kubectl` command to production platform engineering. Each lab includes working manifests, architecture diagrams, interview-ready explanations, and real-world scenarios.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Docker** | Installed and running (`docker --version`) |
| **kubectl** | Kubernetes CLI (`kubectl version --client`) |
| **Minikube or kind** | Local cluster for labs (`minikube start` or `kind create cluster`) |
| **Helm** | Package manager for K8s (`helm version`) |
| **Basic Linux** | Comfortable with terminal, YAML, and shell scripting |

---

## Learning Path Overview

```
Level 1: Beginner (0-2 yrs)     Level 2: Intermediate (2-5 yrs)
┌──────────────────────────┐    ┌──────────────────────────────────┐
│ K8S-01  Core Fundamentals│    │ K8S-05  StatefulSets & Databases │
│ K8S-02  Persistent Storage│   │ K8S-06  Helm Chart Development   │
│ K8S-03  Ingress Controllers│  │ K8S-07  DaemonSets & Resources   │
│ K8S-04  Jobs & CronJobs  │    │ K8S-08  Autoscaling Deep Dive    │
└──────────────────────────┘    │ K8S-09  Advanced Scheduling      │
                                └──────────────────────────────────┘

Level 3: Advanced (5-10 yrs)    Level 4: Expert (10-15+ yrs)
┌──────────────────────────────┐ ┌─────────────────────────────────┐
│ K8S-10  Service Mesh (Istio) │ │ K8S-15  Platform Engineering    │
│ K8S-11  Multi-Tenancy        │ │ K8S-16  Control Plane Internals │
│ K8S-12  Operators & CRDs     │ │ K8S-17  Production Hardening/DR │
│ K8S-13  GitOps at Scale      │ │ K8S-18  Performance & FinOps    │
│ K8S-14  Multi-Cluster Mgmt   │ └─────────────────────────────────┘
└──────────────────────────────┘
```

---

## Level 1: Beginner (0-2 Years Experience)

*Build a solid Kubernetes foundation — understand the objects, deploy applications, expose services, and manage storage.*

| Lab | Title | Key Topics | Time |
|-----|-------|------------|------|
| [K8S-01](K8S-01-core-fundamentals/) | **Core Fundamentals** | Pods, Deployments, Services, ConfigMaps, Secrets, Namespaces, Probes | 3-4 hrs |
| [K8S-02](K8S-02-persistent-storage/) | **Persistent Storage** | PV, PVC, StorageClasses, Dynamic Provisioning, Volume Expansion | 2-3 hrs |
| [K8S-03](K8S-03-ingress-controllers/) | **Ingress Controllers** | NGINX Ingress, TLS, cert-manager, Host/Path routing, Gateway API | 3-4 hrs |
| [K8S-04](K8S-04-jobs-cronjobs/) | **Jobs, CronJobs & Init Containers** | Batch workloads, Sidecars, Init Containers, Container lifecycle | 2-3 hrs |

**After Level 1 you can:** Deploy stateless apps, expose them externally with TLS, persist data, and run batch jobs.

---

## Level 2: Intermediate (2-5 Years Experience)

*Run stateful workloads, author Helm charts, govern resources, auto-scale, and control pod placement.*

| Lab | Title | Key Topics | Time |
|-----|-------|------------|------|
| [K8S-05](K8S-05-statefulsets-databases/) | **StatefulSets & Databases** | PostgreSQL/MongoDB on K8s, Headless Services, Ordered pod management | 3-4 hrs |
| [K8S-06](K8S-06-helm-chart-development/) | **Helm Chart Development** | Chart authoring, Hooks, Sub-charts, Testing, Publishing, Helmfile | 3-4 hrs |
| [K8S-07](K8S-07-daemonsets-resource-governance/) | **DaemonSets & Resource Governance** | DaemonSets, QoS Classes, ResourceQuotas, LimitRanges, PriorityClasses | 2-3 hrs |
| [K8S-08](K8S-08-autoscaling-deep-dive/) | **Autoscaling Deep Dive** | HPA v2, VPA, Karpenter, KEDA, Custom Metrics, Prometheus Adapter | 3-4 hrs |
| [K8S-09](K8S-09-advanced-scheduling/) | **Advanced Scheduling** | Node/Pod Affinity, Taints/Tolerations, Topology Spread, Descheduler | 2-3 hrs |

**After Level 2 you can:** Run databases in K8s, package apps with Helm, set resource budgets, auto-scale on custom metrics, and control exactly where pods land.

---

## Level 3: Advanced (5-10 Years Experience)

*Implement service mesh, multi-tenancy, custom operators, GitOps pipelines, and multi-cluster architectures.*

| Lab | Title | Key Topics | Time |
|-----|-------|------------|------|
| [K8S-10](K8S-10-service-mesh-istio/) | **Service Mesh (Istio)** | mTLS, Traffic splitting, Fault injection, Circuit breaking, Kiali | 4-5 hrs |
| [K8S-11](K8S-11-multi-tenancy/) | **Multi-Tenancy** | vCluster, HNC, Tenant isolation, Kyverno policies, Cost allocation | 3-4 hrs |
| [K8S-12](K8S-12-operators-crds/) | **Operators & CRDs** | CRD design, Operator SDK (Go), Reconciliation, Webhooks, OLM | 4-5 hrs |
| [K8S-13](K8S-13-gitops-at-scale/) | **GitOps at Scale** | Kustomize overlays, ApplicationSets, Multi-env promotion, Image Updater | 3-4 hrs |
| [K8S-14](K8S-14-multi-cluster/) | **Multi-Cluster Management** | Rancher Fleet, Submariner, Liqo, Thanos, Cluster API | 4-5 hrs |

**After Level 3 you can:** Secure service-to-service traffic, isolate tenants, extend K8s with custom resources, deploy across environments with GitOps, and manage multi-cluster fleets.

---

## Level 4: Expert (10-15+ Years Experience)

*Build internal developer platforms, understand control plane internals, harden for production, and optimize cost/performance.*

| Lab | Title | Key Topics | Time |
|-----|-------|------------|------|
| [K8S-15](K8S-15-platform-engineering/) | **Platform Engineering** | Backstage, Crossplane, Golden Paths, Self-service infrastructure | 4-5 hrs |
| [K8S-16](K8S-16-control-plane-internals/) | **Control Plane Internals** | etcd backup/restore, API Server tuning, Scheduler plugins, Upgrades | 3-4 hrs |
| [K8S-17](K8S-17-production-hardening-dr/) | **Production Hardening & DR** | Pod Security Standards, Velero, HA, Supply chain security, DR Runbooks | 4-5 hrs |
| [K8S-18](K8S-18-performance-finops/) | **Performance Engineering & FinOps** | Cilium/eBPF, Kubecost, Benchmarks, Capacity Planning, Bin-packing | 3-4 hrs |

**After Level 4 you can:** Build self-service platforms, debug control plane issues, execute disaster recovery, and optimize cluster cost and performance at scale.

---

## Cross-References to Existing Portfolio Labs

These Kubernetes labs complement the following existing portfolio labs:

| Existing Lab | Related K8s Lab | Connection |
|-------------|----------------|------------|
| [Lab 05 — CI/CD & Kubernetes](../05-cicd-kubernetes/) | K8S-01, K8S-13 | Builds on deployment fundamentals, extends into GitOps |
| [Lab 06 — CI/CD GitOps](../06-cicd-gitops/) | K8S-13 | GitOps at Scale deepens ArgoCD patterns |
| [Lab 07 — ArgoCD Rollouts](../07-cicd-argocd-rollouts/) | K8S-08, K8S-13 | Canary/Blue-Green strategies + autoscaling |
| [Lab 08 — K8s Observability](../08-kubernetes-observability/) | K8S-08, K8S-18 | Metrics feed autoscaling and FinOps |
| [Lab 10 — Logging & Tracing](../10-logging-tracing-pipeline/) | K8S-10, K8S-18 | Istio tracing + performance analysis |
| [Lab 11 — Incident Response](../11-incident-response-slo/) | K8S-17 | DR runbooks and production hardening |
| [Lab 14 — Chaos Engineering](../14-chaos-engineering-litmus/) | K8S-12, K8S-17 | CRD-based chaos + resilience testing |
| [Lab 16 — K8s Security](../16-kubernetes-security/) | K8S-11, K8S-17 | RBAC/NetworkPolicies + hardening |

---

## Suggested Learning Order

**New to Kubernetes?** Follow the labs in order: K8S-01 → K8S-18.

**Already have experience?** Jump to your level:
- **1-2 years:** Start at K8S-05 (StatefulSets)
- **3-5 years:** Start at K8S-10 (Service Mesh)
- **5+ years:** Start at K8S-15 (Platform Engineering)

**Preparing for CKA/CKAD?** Focus on: K8S-01, K8S-02, K8S-03, K8S-04, K8S-05, K8S-07, K8S-09

**Preparing for CKS?** Focus on: K8S-11, K8S-17, plus [Lab 16](../16-kubernetes-security/)

---

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
