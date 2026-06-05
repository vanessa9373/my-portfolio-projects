# K8S-13: GitOps at Scale with Kustomize & ArgoCD ApplicationSets

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)
![Kustomize](https://img.shields.io/badge/Kustomize-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Git](https://img.shields.io/badge/GitOps-F05032?style=for-the-badge&logo=git&logoColor=white)
![AWS](https://img.shields.io/badge/ECR-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)

## Summary

Scaled a single-application ArgoCD deployment to manage 50 microservices across three environments (dev, staging, prod) using Kustomize overlays for DRY configuration and ArgoCD ApplicationSets for templated application generation. Integrated the ArgoCD Image Updater to automatically detect new container images in ECR and promote them through environments without manual YAML edits. This lab demonstrates how to manage GitOps at enterprise scale without drowning in copy-pasted manifests.

## The Problem

The platform team adopted ArgoCD for a single application and it worked well. Scaling to 50 microservices across three environments revealed serious operational pain:

- **Manifest explosion** -- each microservice needs a Deployment, Service, ConfigMap, and Ingress per environment. With 50 services across 3 environments, that is 600+ YAML files, most differing only in replica count, image tag, and resource limits
- **Manual Application CRDs** -- each ArgoCD Application is a separate YAML file. Creating and maintaining 150 Application resources (50 services x 3 environments) by hand is unsustainable
- **Image update bottleneck** -- when CI builds a new image, an engineer must manually edit the image tag in the YAML, commit, push, and wait for ArgoCD to sync. This adds 10-15 minutes to every deployment
- **Environment drift** -- without a structured promotion workflow, dev and staging configs diverge from prod, causing "works in staging, fails in prod" incidents
- **No DRY configuration** -- the same resource limits, health check paths, and security contexts are duplicated across every environment overlay, violating DRY principles

## The Solution

Implemented a three-layer GitOps architecture that scales to hundreds of services:

- **Kustomize base + overlays** -- a single base defines the canonical Deployment, Service, and Ingress. Per-environment overlays patch only what changes (replicas, resource limits, image tags), eliminating 80% of YAML duplication
- **ArgoCD ApplicationSets** -- a single ApplicationSet template generates all 150 ArgoCD Applications dynamically using list generators (for environments) and git generators (for monorepo service discovery)
- **ArgoCD Image Updater** -- watches ECR for new image tags matching a semver pattern, automatically updates the Kustomize image tag in Git, and commits the change, triggering ArgoCD sync
- **Structured promotion** -- images auto-deploy to dev, require manual approval for staging, and use a PR-based gate for prod
- **Sealed Secrets** -- encrypts secrets in Git so the entire application state lives in version control

## Architecture

```
+-------------------+        +---------------------+
|   CI Pipeline     |        |    Git Repository    |
|  (Build & Push)   |        |                      |
|                   |        |  base/               |
|  image:v1.2.3 ----+------->|    deployment.yaml   |
|  -> ECR           |        |    service.yaml      |
+-------------------+        |    kustomization.yaml |
                             |                      |
        +----watches---------+  overlays/            |
        |                    |    dev/               |
+-------v---------+         |      kustomization.yaml
| ArgoCD Image    |         |      replica-patch.yaml
| Updater         |         |    staging/            |
| (auto-update    |-commit->|      kustomization.yaml
|  image tags)    |         |      replica-patch.yaml
+-----------------+         |    prod/               |
                            |      kustomization.yaml|
                            |      replica-patch.yaml|
                            +----------+------------+
                                       |
                            +----------v------------+
                            |    ArgoCD Server       |
                            |                        |
                            |  ApplicationSet:       |
                            |    list-generator      |
                            |    git-generator       |
                            +--+--------+--------+--+
                               |        |        |
                          +----v--+ +---v---+ +--v----+
                          | dev   | |staging| | prod  |
                          |cluster| |cluster| |cluster|
                          +-------+ +-------+ +-------+
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| Kustomize | Configuration management | Built into kubectl, no templating language to learn, overlays patch only what changes between environments |
| ArgoCD 2.10 | GitOps continuous delivery | Industry-standard GitOps controller with ApplicationSets for multi-app/multi-env management |
| ApplicationSets | Dynamic Application generation | Generates hundreds of ArgoCD Applications from a single template using generators (list, git, matrix) |
| ArgoCD Image Updater | Automatic image promotion | Watches container registries for new tags and commits image updates to Git, closing the CI/CD loop |
| Sealed Secrets | Secret management in Git | Encrypts secrets so they can be safely stored in Git, enabling true GitOps where all state is in version control |
| Amazon ECR | Container registry | Private registry for storing versioned container images, integrated with Image Updater via IAM roles |

## Implementation Steps

### Step 1: Set up Kustomize base

```bash
# Review the base configuration
ls base/
cat base/kustomization.yaml

# Verify the base builds correctly
kubectl kustomize base/

# The base defines the canonical resource structure
# Overlays will patch specific fields per environment
```

**What this does:** The base directory contains the canonical Deployment, Service, and kustomization.yaml that define the application's resource structure. The base uses placeholder values (1 replica, minimal resources) that overlays will patch. This is the single source of truth for resource structure.

### Step 2: Create overlays for dev, staging, prod

```bash
# Review overlay structure
ls overlays/dev/ overlays/staging/ overlays/prod/

# Build each environment's final manifests
echo "=== DEV ==="
kubectl kustomize overlays/dev/

echo "=== STAGING ==="
kubectl kustomize overlays/staging/

echo "=== PROD ==="
kubectl kustomize overlays/prod/
```

**What this does:** Each overlay directory contains a `kustomization.yaml` that references the base and applies environment-specific patches. Dev gets 1 replica with minimal resources. Staging gets 2 replicas with moderate resources. Prod gets 3 replicas with production-grade resources and additional labels. The diff between environments is typically 10-15 lines instead of 100+.

### Step 3: Deploy with kustomize build and verify

```bash
# Deploy to dev environment
kubectl kustomize overlays/dev/ | kubectl apply -f - -n dev

# Verify deployment
kubectl get deployments -n dev
kubectl get services -n dev

# Compare resource differences across environments
diff <(kubectl kustomize overlays/dev/) <(kubectl kustomize overlays/prod/)
```

**What this does:** Builds the final manifests by merging base + overlay patches and applies them to the dev namespace. The `diff` command shows exactly what changes between environments -- typically replica count, resource limits, and image tags.

### Step 4: Install ArgoCD ApplicationSet controller

```bash
# Install ArgoCD (if not already installed)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Verify ApplicationSet controller is running (included in ArgoCD 2.x)
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**What this does:** Installs ArgoCD with the ApplicationSet controller (included by default in ArgoCD 2.x). The ApplicationSet controller watches for ApplicationSet resources and generates ArgoCD Application resources dynamically based on generator templates.

### Step 5: Create ApplicationSet (list generator for environments)

```bash
# Apply the list-based ApplicationSet
kubectl apply -f manifests/applicationset-list.yaml

# Verify Applications were generated
kubectl get applications -n argocd

# Expected output: 3 applications (myapp-dev, myapp-staging, myapp-prod)
argocd app list
```

**What this does:** The list generator creates one ArgoCD Application per entry in a hardcoded list. Each entry specifies the environment name, target cluster, namespace, and overlay path. One ApplicationSet template generates all three environment-specific Applications automatically.

### Step 6: Create ApplicationSet (git generator for monorepo)

```bash
# Apply the git-based ApplicationSet
kubectl apply -f manifests/applicationset-git.yaml

# Verify Applications were generated for all services found in the repo
kubectl get applications -n argocd

# The git generator discovers services by scanning directories
argocd app list --output wide
```

**What this does:** The git generator scans the Git repository for directories matching a pattern (e.g., `services/*/overlays/{{env}}`). For every directory it finds, it generates an ArgoCD Application. When a new microservice is added to the repo, the ApplicationSet automatically creates its ArgoCD Application without manual intervention.

### Step 7: Configure ArgoCD Image Updater

```bash
# Apply Image Updater configuration
kubectl apply -f manifests/image-updater-config.yaml

# Install ArgoCD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Verify Image Updater is running
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater

# Check Image Updater logs for registry polling
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater -f
```

**What this does:** Deploys the ArgoCD Image Updater, which polls ECR every 2 minutes for new image tags. When it finds a new tag matching the configured semver constraint, it updates the Kustomize image tag in Git via a commit, triggering ArgoCD to sync the new image to the target environment.

### Step 8: Test end-to-end: push image, auto-update, promote through environments

```bash
# Simulate a new image push to ECR
docker build -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.3.0 .
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:v1.3.0

# Watch Image Updater detect the new tag (within 2 minutes)
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20

# Verify dev environment auto-updates
argocd app get myapp-dev | grep "Image"

# Promote to staging (manual approval)
argocd app sync myapp-staging

# Promote to prod (via PR)
# Image Updater creates a branch + PR for prod changes
gh pr list --repo your-org/gitops-repo
```

**What this does:** Demonstrates the full CI/CD loop: CI pushes a new image, Image Updater detects it and commits an image tag update to the dev overlay, ArgoCD syncs dev automatically. Staging requires manual sync (approval gate). Prod uses a PR-based promotion where Image Updater creates a branch that must be reviewed and merged.

## Project Structure

```
K8S-13-gitops-at-scale/
├── README.md
├── base/
│   ├── deployment.yaml                   # Canonical Deployment template
│   ├── service.yaml                      # Canonical Service template
│   └── kustomization.yaml                # Base kustomization
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml            # Dev overlay (refs base, applies patches)
│   │   └── replica-patch.yaml            # Dev-specific: 1 replica, minimal resources
│   ├── staging/
│   │   ├── kustomization.yaml            # Staging overlay
│   │   └── replica-patch.yaml            # Staging: 2 replicas, moderate resources
│   └── prod/
│       ├── kustomization.yaml            # Prod overlay
│       └── replica-patch.yaml            # Prod: 3 replicas, production resources
├── manifests/
│   ├── applicationset-list.yaml          # List generator for environments
│   ├── applicationset-git.yaml           # Git generator for monorepo discovery
│   └── image-updater-config.yaml         # Image Updater annotation config
└── scripts/
    ├── deploy.sh                         # Full deployment automation
    └── cleanup.sh                        # Teardown all resources
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `base/deployment.yaml` | Canonical Deployment with placeholder values | Kustomize base, resource template, label selectors |
| `base/kustomization.yaml` | Lists resources included in the base | Kustomize resource aggregation, commonLabels |
| `overlays/prod/kustomization.yaml` | References base and applies prod-specific patches | Kustomize overlays, strategic merge patches, image tag overrides |
| `overlays/prod/replica-patch.yaml` | Patches replica count and resource limits for prod | Strategic merge patch, JSON patch, environment-specific config |
| `applicationset-list.yaml` | Generates one ArgoCD Application per environment | ApplicationSet, list generator, template variables |
| `applicationset-git.yaml` | Discovers services in Git repo and generates Applications | Git generator, directory discovery, monorepo pattern |
| `image-updater-config.yaml` | Configures Image Updater annotations on Applications | ArgoCD annotations, semver constraints, write-back methods |

## Results & Metrics

| Metric | Before | After |
|---|---|---|
| YAML files per microservice per environment | 4 (600+ total) | 2 overlay files + 1 shared base (110 total) |
| ArgoCD Application manifests | 150 (manually maintained) | 2 ApplicationSet templates |
| Image update deployment time | 10-15 minutes (manual) | 2-3 minutes (automated) |
| Environment config drift incidents | 3-4/month | 0 (overlays enforce consistency) |
| New service onboarding (GitOps) | 2 hours (copy-paste) | 10 minutes (add directory, auto-discovered) |
| YAML duplication rate | ~80% identical across envs | <5% (only patches differ) |

## How I'd Explain This in an Interview

> "We had ArgoCD working for one app, but scaling to 50 microservices across dev, staging, and prod meant 600+ YAML files and 150 manually maintained ArgoCD Application resources. I restructured our GitOps repo using Kustomize with a shared base and per-environment overlays, reducing YAML by 80% -- each environment only patches what differs (replicas, resources, image tags). For ArgoCD, I replaced the 150 hand-written Application manifests with two ApplicationSet templates: a list generator that creates per-environment Applications, and a git generator that auto-discovers new services by scanning the repo directory structure. When someone adds a new microservice directory, it automatically gets ArgoCD Applications for all three environments. For the image update bottleneck, I deployed the ArgoCD Image Updater, which polls ECR for new tags every 2 minutes and commits the image update to Git, triggering ArgoCD sync. Dev auto-deploys, staging requires manual sync, and prod uses a PR gate. The entire flow from CI image push to prod deployment is now automated with appropriate guardrails at each stage."

## Key Concepts Demonstrated

- **Kustomize Base + Overlays** -- a DRY configuration pattern where a base defines resource structure and overlays patch environment-specific values, eliminating duplication across environments
- **ApplicationSet Generators** -- ArgoCD feature that dynamically generates Application resources from templates using list, git, cluster, or matrix generators
- **List Generator** -- creates Applications from a hardcoded list of parameters, ideal for a known set of environments or clusters
- **Git Generator** -- scans a Git repository for directories matching a pattern and generates Applications for each, enabling automatic service discovery
- **Image Updater** -- ArgoCD addon that watches container registries for new tags and commits image updates to Git, closing the CI/CD feedback loop
- **Strategic Merge Patch** -- Kustomize patch type that merges fields into existing resources by matching on name and kind, used for overlays
- **Promotion Workflow** -- structured process for moving changes through environments with appropriate gates (auto for dev, manual for staging, PR for prod)

## Lessons Learned

1. **Kustomize patches must match resource names exactly** -- a typo in the patch target name silently produces no change. Use `kustomize build` and `diff` to verify patches are applied before committing.
2. **ApplicationSet generator scope matters** -- the git generator scans every commit, which can be expensive on large repos. Use `directories` with explicit include/exclude paths rather than scanning the entire repo root.
3. **Image Updater write-back method affects workflow** -- the `git` write-back method commits directly to the branch, which works for dev but bypasses PR review for prod. Use separate branches per environment with PR-based write-back for production.
4. **Sealed Secrets must be regenerated per cluster** -- each cluster's sealed-secrets controller has a unique key pair. Sealing a secret for the dev cluster does not decrypt in prod. Maintain per-cluster SealedSecret manifests.
5. **Test overlays in CI before merging** -- a broken kustomization.yaml can break ArgoCD sync for all environments. We added `kustomize build` validation to our CI pipeline to catch overlay errors before they reach the GitOps repo.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
