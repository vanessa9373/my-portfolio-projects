# Lab 05: CI/CD Pipeline & Kubernetes Deployment Platform

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=flat&logo=argo&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat&logo=terraform&logoColor=white)

## Summary (The "Elevator Pitch")

Built a fully automated GitOps CI/CD platform using GitHub Actions, ArgoCD, and Amazon EKS. Developers push code, and the system automatically tests, builds, scans, and deploys — with zero-downtime rollouts and 30-second rollbacks. Increased deployment frequency from once a month to 10 times a day.

## The Problem

Deployments were manual — an engineer would SSH into a server, pull the latest code, restart services, and hope nothing broke. This took 15-30 minutes per deploy, caused downtime, and happened only once a month because it was so risky. Rollbacks meant reverting git commits and redeploying, which took hours.

## The Solution

Built a **GitOps pipeline** where pushing to `main` triggers automatic testing, Docker image building, security scanning, and deployment to Kubernetes via ArgoCD. ArgoCD continuously watches the git repo and syncs the cluster to match — if something breaks, rollback is a single `git revert`.

## Architecture

```
 Developer ──► GitHub Push ──► GitHub Actions Pipeline
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
                 Lint/Test     Docker Build     Security Scan
                    │               │               │
                    └───────────────┼───────────────┘
                                    ▼
                              Push to ECR
                                    │
                    ┌───────────────┼───────────────┐
                    ▼                               ▼
              ArgoCD Sync                     ArgoCD Sync
           (Staging - Auto)              (Production - Manual)
                    │                               │
                    ▼                               ▼
            ┌──────────────┐                ┌──────────────┐
            │  EKS Staging │                │   EKS Prod   │
            │  ┌────────┐  │                │  ┌────────┐  │
            │  │ Pods   │  │                │  │ Pods   │  │
            │  │ HPA    │  │                │  │ HPA    │  │
            │  │ Ingress│  │                │  │ Ingress│  │
            │  └────────┘  │                │  └────────┘  │
            └──────────────┘                └──────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| GitHub Actions | CI pipeline (test, build, scan) | Native GitHub integration, free for public repos |
| ArgoCD | GitOps continuous deployment | Declarative, auto-sync, visual dashboard |
| Amazon EKS | Kubernetes cluster | Managed control plane, IAM integration |
| ECR | Container registry | Private, encrypted, native EKS integration |
| Terraform | Infrastructure provisioning | EKS cluster, VPC, IAM roles as code |
| Helm | Kubernetes package management | Templated deployments, release management |

## Implementation Steps

### Step 1: Provision EKS Cluster
**What this does:** Creates the EKS cluster, VPC, managed node groups, and IAM roles using Terraform.
```bash
cd terraform
terraform init && terraform apply
aws eks update-kubeconfig --name cicd-platform-cluster --region us-west-2
```

### Step 2: Install ArgoCD
**What this does:** Deploys ArgoCD into the cluster. ArgoCD watches your git repo and automatically syncs deployments.
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Deploy Application Manifests
**What this does:** Applies Kubernetes deployment (with rolling update strategy), service, HPA (auto-scaling), and ArgoCD application definition.
```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/argocd/application.yaml
```

### Step 4: Configure GitHub Actions Secrets
**What this does:** Adds AWS credentials and cluster info to GitHub so the CI pipeline can push images and update deployments.
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- `ECR_REGISTRY` — your ECR registry URL
- `EKS_CLUSTER_NAME` — cluster name

### Step 5: Push and Deploy
**What this does:** Any push to `main` triggers the full pipeline — lint, test, build, scan, push to ECR, ArgoCD auto-syncs.
```bash
git push origin main   # Triggers CI/CD automatically
```

## Project Structure

```
05-cicd-kubernetes/
├── README.md
├── terraform/
│   ├── main.tf                  # EKS cluster, VPC, IAM, ECR
│   ├── variables.tf             # Cluster config variables
│   └── outputs.tf               # Cluster endpoint, ECR URL
├── k8s/
│   ├── deployment.yaml          # Deployment with rolling update strategy
│   ├── service.yaml             # ClusterIP service + ALB Ingress
│   ├── hpa.yaml                 # Horizontal Pod Autoscaler (CPU-based)
│   └── argocd/
│       └── application.yaml     # ArgoCD Application for GitOps sync
└── .github/
    └── workflows/
        └── ci-cd.yaml           # Full pipeline: lint → test → build → scan → deploy
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `.github/workflows/ci-cd.yaml` | Full CI/CD pipeline — lint, test, Docker build, Trivy scan, push to ECR | GitHub Actions, multi-stage pipelines |
| `k8s/deployment.yaml` | Kubernetes deployment with rolling update strategy and health probes | Rolling updates, readiness/liveness probes |
| `k8s/hpa.yaml` | Auto-scales pods from 2-10 based on CPU utilization (target: 70%) | Horizontal scaling, resource management |
| `k8s/argocd/application.yaml` | Tells ArgoCD which repo/path to watch and auto-sync to the cluster | GitOps, declarative deployment |
| `terraform/main.tf` | EKS cluster with managed nodes, VPC, ECR registry | Managed Kubernetes, IAM roles |

## Results & Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Deploy Frequency | 1x/month | 10x/day | **10x increase** |
| Deployment Downtime | 15-30 min | 0 min | **Zero-downtime** |
| Provisioning Time | 2 weeks | 30 min | **80% faster** |
| Rollback Time | 2 hours | 30 seconds | **99% faster** |

## How I'd Explain This in an Interview

> "Deployments were manual SSH-and-pray — 15-30 minutes of downtime each time, happening once a month. I built a GitOps CI/CD pipeline where pushing to main triggers GitHub Actions to lint, test, build a Docker image, scan it for vulnerabilities with Trivy, and push to ECR. ArgoCD watches the git repo and auto-syncs the deployment to EKS. Rollbacks are just a git revert — 30 seconds instead of 2 hours. We went from 1 deploy/month to 10/day with zero downtime."

## Key Concepts Demonstrated

- **GitOps** — Git as the single source of truth for deployments
- **CI/CD Pipeline** — Automated test → build → scan → deploy
- **Zero-Downtime Deployments** — Rolling update strategy with health probes
- **Auto-Scaling** — HPA scales pods based on CPU utilization
- **Container Security** — Trivy vulnerability scanning in the pipeline
- **Infrastructure as Code** — EKS cluster provisioned via Terraform

## Lessons Learned

1. **ArgoCD auto-sync is powerful but dangerous** — use it for staging, require manual sync for production
2. **Health probes are critical** — without readiness probes, Kubernetes routes traffic to unready pods
3. **Scan images before deploying** — Trivy catches CVEs that would otherwise reach production
4. **HPA needs resource requests** — auto-scaling only works if pods declare CPU/memory requests
5. **GitOps simplifies rollbacks** — `git revert` + ArgoCD auto-sync = instant rollback

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
