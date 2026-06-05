# Lab 05: CI/CD Pipeline & Kubernetes Deployment Platform — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars)  
> **Scope:** End-to-end GitOps pipeline — code commit → test → build → scan → EKS deploy

---

## What This Platform Solves

Monthly deployments with 15–30 minutes of downtime are not a deployment process problem — they are a confidence problem. Teams deploy infrequently because deployments are risky. Deployments are risky because they're manual. Manual deployments are manual because automating them is harder than doing them manually once. The GitOps platform breaks this loop: every deployment is automated, tested, and reversible. The risk of deploying 10 times a day is lower than deploying once a month manually.

---

## Step-by-Step: Infrastructure Provisioning

### Step 1 — EKS Cluster via Terraform

```hcl
# terraform/main.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  
  cluster_name    = "cicd-platform-cluster"
  cluster_version = "1.28"
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  # OIDC provider for IRSA
  enable_irsa = true
  
  eks_managed_node_groups = {
    general = {
      min_size       = 2
      max_size       = 6
      desired_size   = 3
      instance_types = ["m5.large"]
      
      # IMDSv2 required
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }
    }
  }
}
```

**Why managed node groups over self-managed?**  
Self-managed node groups require managing: AMI selection, AMI updates, kubelet configuration, bootstrap scripts, and node group lifecycle. Managed node groups handle all of this — AWS provides the EKS-optimized AMI, applies updates, and manages node replacement. For a CI/CD platform where the cluster is infrastructure, not the product, managed node groups eliminate operational overhead.

**Why `desired_size = 3` across 3 AZs?**  
With 3 nodes across 3 AZs, Kubernetes can schedule 3 replicas of a deployment (one per AZ) with guaranteed AZ diversity. A single AZ failure reduces capacity to 2/3 without causing an outage. With 2 nodes, a 2-node cluster with 2 replicas loses 50% capacity on AZ failure — often insufficient for the traffic load.

### Step 2 — ECR Repository

```hcl
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "IMMUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  lifecycle {
    prevent_destroy = true  # don't delete registry with terraform destroy
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
```

**Why `IMMUTABLE` tags?**  
Tag mutability means `docker push ecr/app:v1.0.0` can overwrite an existing `v1.0.0` image. If ArgoCD is tracking `image: app:v1.0.0` and a broken build overwrites that tag, the cluster auto-deploys the broken version — with no git commit to track the change. Immutable tags make this impossible: once pushed, `v1.0.0` always refers to the same image digest.

---

## Step-by-Step: GitHub Actions CI Pipeline

### Step 3 — Pipeline Structure

```yaml
# .github/workflows/ci-cd.yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AWS_REGION: us-west-2
  ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
  IMAGE_TAG: ${{ github.sha }}  # Git SHA as image tag — unique, traceable

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: pip install -r requirements.txt -r requirements-dev.txt
      
      - name: Run linting
        run: flake8 src/ --max-line-length=100
      
      - name: Run tests
        run: pytest tests/ --cov=src --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3

  build-and-deploy:
    needs: lint-and-test  # only runs if tests pass
    if: github.ref == 'refs/heads/main'  # only deploy on main
    runs-on: ubuntu-latest
    
    permissions:
      id-token: write  # required for OIDC
      contents: read
    
    steps:
      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-ecr
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2
      
      - name: Build Docker image
        run: |
          docker build -t $ECR_REGISTRY/${{ env.APP_NAME }}:${{ env.IMAGE_TAG }} .
          docker build -t $ECR_REGISTRY/${{ env.APP_NAME }}:latest .
      
      - name: Run Trivy security scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.ECR_REGISTRY }}/${{ env.APP_NAME }}:${{ env.IMAGE_TAG }}
          exit-code: '1'
          severity: 'CRITICAL,HIGH'
      
      - name: Push to ECR
        run: |
          docker push $ECR_REGISTRY/${{ env.APP_NAME }}:${{ env.IMAGE_TAG }}
          docker push $ECR_REGISTRY/${{ env.APP_NAME }}:latest
      
      - name: Update Kubernetes manifest
        run: |
          sed -i "s|image: .*${{ env.APP_NAME }}:.*|image: $ECR_REGISTRY/${{ env.APP_NAME }}:${{ env.IMAGE_TAG }}|" \
            k8s/deployment.yaml
          git config --global user.email "github-actions@github.com"
          git config --global user.name "GitHub Actions"
          git add k8s/deployment.yaml
          git commit -m "ci: update image to ${{ env.IMAGE_TAG }}"
          git push
```

**Why `github.sha` as the image tag instead of a version number?**  
Git SHA is the canonical identifier for a specific state of the codebase. It:
- Is globally unique
- Links the image directly to the commit that built it (`git show abc1234` shows exactly what changed)
- Doesn't require a version bumping step in the pipeline
- Makes "what code is running in production?" answerable by looking at the image tag

**Why `needs: lint-and-test` before `build-and-deploy`?**  
Without the dependency, both jobs run in parallel — a broken build could deploy to ECR before tests fail. The `needs` gate ensures the ECR push only happens after all tests pass.

**Why Trivy blocking on HIGH + CRITICAL (not just CRITICAL)?**  
Lab 05 is more conservative than the EKS project (which only blocks on CRITICAL). HIGH CVEs (CVSS 7.0–8.9) include important but harder-to-exploit vulnerabilities. For a platform that manages deployments (and therefore has broad cluster access), blocking HIGH CVEs is the right security posture.

### Step 4 — OIDC Authentication

```json
// IAM Role Trust Policy
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:ref:refs/heads/main"
      }
    }
  }]
}
```

**Why the `ref:refs/heads/main` condition?**  
Without this condition, any branch in the repository can assume this role. A developer pushing to a feature branch could deploy to production. The `ref` condition restricts role assumption to the `main` branch only — ensuring only reviewed, merged code can deploy.

---

## Step-by-Step: Kubernetes Deployment

### Step 5 — Deployment Manifest with Rolling Updates

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1         # create 1 extra pod during update (4 total briefly)
      maxUnavailable: 0   # never have fewer than 3 ready pods
  
  selector:
    matchLabels:
      app: web
  
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: app
          image: ACCOUNT.dkr.ecr.us-west-2.amazonaws.com/app:latest  # ArgoCD updates this
          
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          
          readinessProbe:   # don't route traffic until ready
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3
          
          livenessProbe:    # restart if unhealthy
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3
```

**Why `maxUnavailable: 0` with `maxSurge: 1`?**  
- `maxUnavailable: 0` means: never terminate an old pod until a new pod is Ready. Zero downtime.
- `maxSurge: 1` means: create 1 new pod before terminating an old one. Temporarily uses 4 pods worth of resources during rollout.
- Alternative (`maxUnavailable: 1, maxSurge: 0`): terminate 1 old pod then create 1 new pod. Temporarily serves 2 pods instead of 3 — capacity drops during rollout. Acceptable for non-critical services.

**Why `readinessProbe` AND `livenessProbe`?**  
Two different questions:
- **Readiness:** "Is this pod ready to receive traffic?" Failed readiness → removed from Service endpoints, not restarted. Used during startup (`initialDelaySeconds: 10`) and for temporary load shedding.
- **Liveness:** "Is this pod alive?" Failed liveness → pod killed and restarted. Used to detect deadlocks or hangs that don't crash the process.

A pod that started but isn't ready shouldn't receive traffic (readiness handles this). A pod that's hung in an infinite loop should be restarted (liveness handles this). Using only one probe misses one of these failure modes.

**Why resource `requests` AND `limits`?**  
- `requests`: What Kubernetes reserves for this container when scheduling. Kubernetes only places the pod on a node with this much available.
- `limits`: Maximum the container can use. If exceeded: CPU is throttled (not killed), memory causes an OOM kill.
- **HPA requires requests:** The Horizontal Pod Autoscaler computes CPU utilization as `actual CPU / requested CPU`. Without requests, HPA has no denominator and cannot scale.

### Step 6 — Horizontal Pod Autoscaler

```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

**Why 70% CPU target, not 80%?**  
HPA has a reaction delay: it detects CPU > 70%, waits for the stabilization window (default 5 minutes for scale-out to prevent thrashing), then adds a replica. If the target is 80%, by the time new replicas are ready, CPU may be at 95% and users experience degraded performance. A 70% target provides a 30% buffer during scale-out latency.

**Why `minReplicas: 2`?**  
A single replica is a single point of failure. If the only replica restarts (OOM kill, node failure, deployment), the service is completely unavailable during the restart (~30 seconds). Two replicas provides a hot standby.

### Step 7 — ArgoCD GitOps Sync

```yaml
# k8s/argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cicd-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/OWNER/REPO
    targetRevision: HEAD
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true       # delete resources removed from Git
      selfHeal: true    # revert manual kubectl changes
    syncOptions:
      - CreateNamespace=true
```

**ArgoCD sync lifecycle:**
1. CI pipeline commits updated `deployment.yaml` (new image tag) to Git
2. ArgoCD polls the repository every 3 minutes (or receives a webhook for near-instant sync)
3. ArgoCD diffs the current cluster state against the desired state in Git
4. ArgoCD applies the diff (`kubectl apply` equivalent)
5. Kubernetes performs the rolling update
6. ArgoCD reports health: Healthy | Progressing | Degraded

**Rollback mechanism:**
```bash
# Option 1: Git-based (recommended)
git revert HEAD  # creates a new commit reverting the image tag change
git push         # ArgoCD detects and syncs — cluster reverts to previous version

# Option 2: ArgoCD history
argocd app history cicd-app
argocd app rollback cicd-app <revision-id>
```

Git-based rollback is preferred because it preserves history (the rollback is itself a commit) and is repeatable — multiple team members can see exactly what was reverted and when.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **Git as single source of truth:** The cluster state always reflects Git state — "what's deployed?" is answered by `git log`
- **Automated deployments:** Zero manual steps between `git push` and production deploy
- **30-second rollback:** `git revert` + ArgoCD auto-sync — faster and more reliable than manual rollback procedures

### Security
- **OIDC instead of stored AWS keys:** GitHub Actions never holds long-lived credentials
- **Trivy blocks HIGH + CRITICAL:** Vulnerable images never reach ECR
- **ECR `scan_on_push`:** Second scan after push — defense in depth
- **Private EKS nodes:** Worker nodes have no public IPs

### Reliability
- **Rolling updates with `maxUnavailable: 0`:** Zero-downtime deployments
- **Readiness probes:** No traffic routed to unready pods
- **Multi-AZ nodes:** Single AZ failure doesn't cause cluster outage
- **HPA:** Handles traffic spikes automatically without manual intervention

### Performance Efficiency
- **HPA 70% target:** Scales before performance degrades, not after
- **Resource requests/limits:** Kubernetes scheduler places pods optimally; no over-provisioned nodes

### Cost Optimization
- **HPA autoscaling:** Scale down during low-traffic periods — `minReplicas: 2` not `desired: 10`
- **ECR lifecycle policy:** 20 images max — ECR storage costs bounded

### Sustainability
- **Kubernetes bin-packing:** Kubernetes scheduler places pods to maximize node utilization — idle EC2 avoided
- **HPA scale-down:** Replicas removed when CPU drops — no idle containers

---

## Key Architectural Insight

The fundamental insight of GitOps is that **Git is the interface between humans and infrastructure**. Humans express intent through Git commits. ArgoCD translates Git state into cluster state. The cluster never diverges from Git because `selfHeal: true` continuously reconciles them. This means: if a new engineer joins and wants to know what's running in production, they read Git — not the cluster, not a deployment log, not a Jira ticket. The entire operational history is version-controlled, auditable, and reversible. This is what makes 10 deployments per day safer than 1 per month: each change is small, auditable, and rollback is one commit.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
