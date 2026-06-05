# Phase 14: Platform Engineering & Developer Portal

**Difficulty:** Expert | **Time:** 6-8 hours | **Prerequisites:** Phase 13

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
9. [Summary](#9-summary)

---

## 1. Overview

Platform engineering is the culmination of the DevOps journey — building an internal developer platform (IDP) that abstracts away infrastructure complexity and enables developers to self-serve. Instead of filing tickets for a database or waiting for DevOps to create a new service, developers use golden path templates and self-service infrastructure.

### Platform Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  Internal Developer Platform                  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Backstage Developer Portal                │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐    │  │
│  │  │ Service  │  │ Software │  │  API Docs        │    │  │
│  │  │ Catalog  │  │Templates │  │  (Swagger/OAS)   │    │  │
│  │  └──────────┘  └──────────┘  └──────────────────┘    │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐    │  │
│  │  │ Tech     │  │ CI/CD    │  │  Cost Dashboard  │    │  │
│  │  │ Radar    │  │ Status   │  │  (Kubecost)      │    │  │
│  │  └──────────┘  └──────────┘  └──────────────────┘    │  │
│  └────────────────────────────────────────────────────────┘  │
│                              │                               │
│                              ▼                               │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              Crossplane (Self-Service Infra)           │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────┐    │  │
│  │  │PostgreSQL│  │  Redis   │  │   RabbitMQ       │    │  │
│  │  │(Aurora)  │  │(ElastiC) │  │  (AmazonMQ)      │    │  │
│  │  └──────────┘  └──────────┘  └──────────────────┘    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Key Results

| Metric | Before | After |
|--------|--------|-------|
| New service setup time | 2-3 days (ticket-based) | 5 minutes (self-service) |
| Services cataloged | 0% | 100% |
| Infrastructure requests | Manual (tickets) | Self-service (Crossplane) |
| API documentation coverage | Scattered | 100% aggregated |
| Developer onboarding | 1-2 weeks | 1-2 days |

### Directory Structure

```
phase-14-platform-engineering/
├── backstage/
│   └── templates/
│       └── new-microservice.yaml    # Golden path template
└── crossplane/
    └── database-composition.yaml    # Self-service database provisioning
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 18+ | Installed in Phase 2 |
| Helm | 3.13+ | Installed in Phase 6 |
| kubectl | 1.28+ | Installed in Phase 4 |

### Install Backstage

```bash
# Create a Backstage app
npx @backstage/create-app@latest

# Install and start
cd backstage
yarn install
yarn dev

# Access at http://localhost:3000
```

### Install Crossplane

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace

# Install the AWS provider
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: xpkg.upbound.io/upbound/provider-aws-rds:v0.47.0
EOF
```

---

## 3. Step-by-Step Implementation

### Step 1: Create the Service Template

The Backstage template defines the "golden path" for creating new microservices. When a developer fills out the form, Backstage automatically:

1. Scaffolds a new service from a language-specific template
2. Creates a GitHub repository with branch protection
3. Sets up an ArgoCD Application for GitOps deployment
4. Registers the service in the Backstage catalog

```bash
# Register the template in Backstage
# Add to app-config.yaml:
catalog:
  locations:
    - type: file
      target: ./templates/new-microservice.yaml
```

### Step 2: Create the Language Skeletons

Create template skeletons for each supported language:

```bash
# Node.js skeleton
mkdir -p skeletons/nodejs/
# Contains: package.json, Dockerfile, src/index.js, .github/workflows/ci.yml, etc.

# Python skeleton
mkdir -p skeletons/python/
# Contains: requirements.txt, Dockerfile, main.py, .github/workflows/ci.yml, etc.
```

### Step 3: Deploy the Crossplane Database Composition

```bash
kubectl apply -f crossplane/database-composition.yaml
```

This creates:
- A `CompositeResourceDefinition` (XRD) that defines the `XDatabase` API
- A `Composition` that maps size (small/medium/large) to Aurora instance classes
- Developers can then create databases by applying a simple YAML:

```yaml
# What a developer submits:
apiVersion: database.ecommerce.com/v1alpha1
kind: XDatabase
metadata:
  name: my-new-service-db
spec:
  parameters:
    size: small          # Maps to db.t4g.medium
    engine: postgresql
    version: "15"
```

### Step 4: Test the End-to-End Flow

```bash
# 1. Developer opens Backstage → Templates → "New Microservice"
# 2. Fills out the form:
#    - Service name: recommendation-service
#    - Language: Node.js (Express)
#    - Database: PostgreSQL
#    - Messaging: RabbitMQ
#    - Cache: Redis
# 3. Clicks "Create"

# Backstage automatically:
# → Creates GitHub repo: org/recommendation-service
# → Scaffolds from Node.js template
# → Creates ArgoCD Application
# → Registers in service catalog

# 4. Developer's database:
kubectl apply -f - <<EOF
apiVersion: database.ecommerce.com/v1alpha1
kind: XDatabase
metadata:
  name: recommendation-service-db
spec:
  parameters:
    size: small
    engine: postgresql
    version: "15"
EOF

# 5. Check database provisioning
kubectl get xdatabase recommendation-service-db
# STATUS: Ready (after 5-10 minutes)
```

### Step 5: Configure the Service Catalog

Register all existing services in the Backstage catalog:

```yaml
# catalog-info.yaml (placed in each service's repo root)
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: user-service
  description: User authentication and profile management
  annotations:
    github.com/project-slug: org/ecommerce-platform
    argocd/app-name: user-service
    backstage.io/techdocs-ref: dir:.
  tags:
    - nodejs
    - postgresql
    - redis
spec:
  type: service
  lifecycle: production
  owner: platform-team
  system: ecommerce
  providesApis:
    - user-api
  consumesApis:
    - notification-api
```

---

## 4. Configuration Walkthrough

### `backstage/templates/new-microservice.yaml` — Section by Section

#### Template Metadata

```yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-microservice
  title: Create a New Microservice
  description: |
    Scaffolds a production-ready microservice with CI/CD,
    Kubernetes deployment, and service catalog registration.
  tags:
    - recommended         # Shows at top of template list
    - microservice
    - nodejs
    - python
```

#### Parameters (Developer Form)

```yaml
spec:
  parameters:
    - title: Service Details
      required: [name, description, owner]
      properties:
        name:
          title: Service Name
          type: string
          description: Lowercase, hyphenated (e.g., recommendation-service)
          pattern: '^[a-z][a-z0-9-]*$'

        description:
          title: Description
          type: string

        owner:
          title: Owner
          type: string
          ui:field: OwnerPicker        # Backstage team picker

    - title: Technical Choices
      properties:
        language:
          title: Language
          type: string
          enum: ['nodejs', 'python']
          enumNames: ['Node.js (Express)', 'Python (FastAPI)']

        database:
          title: Database
          type: string
          enum: ['postgresql', 'none']
          enumNames: ['PostgreSQL', 'None']

        messaging:
          title: Messaging
          type: string
          enum: ['rabbitmq', 'none']
          enumNames: ['RabbitMQ', 'None']

        cache:
          title: Cache
          type: string
          enum: ['redis', 'none']
          enumNames: ['Redis', 'None']
```

#### Steps (Automation)

```yaml
  steps:
    # Step 1: Generate code from template
    - id: fetch-base
      name: Fetch Base Template
      action: fetch:template
      input:
        url: ./skeletons/${{ parameters.language }}
        values:
          name: ${{ parameters.name }}
          description: ${{ parameters.description }}
          database: ${{ parameters.database }}
          messaging: ${{ parameters.messaging }}
          cache: ${{ parameters.cache }}

    # Step 2: Create GitHub repository
    - id: publish
      name: Publish to GitHub
      action: publish:github
      input:
        repoUrl: github.com?owner=org&repo=${{ parameters.name }}
        defaultBranch: main
        protectDefaultBranch: true     # Enable branch protection

    # Step 3: Create ArgoCD Application
    - id: create-argocd-app
      name: Create ArgoCD Application
      action: argocd:create-application
      input:
        appName: ${{ parameters.name }}
        repoUrl: ${{ steps.publish.output.remoteUrl }}
        path: k8s/overlays/production

    # Step 4: Register in Backstage catalog
    - id: register
      name: Register in Catalog
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: /catalog-info.yaml
```

#### Output (Links for Developer)

```yaml
  output:
    links:
      - title: Repository
        url: ${{ steps.publish.output.remoteUrl }}
      - title: ArgoCD Application
        url: https://argocd.ecommerce.com/applications/${{ parameters.name }}
      - title: Service Catalog Entry
        icon: catalog
        entityRef: ${{ steps.register.output.entityRef }}
```

### `crossplane/database-composition.yaml` — Key Sections

#### CompositeResourceDefinition (XRD)

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xdatabases.database.ecommerce.com
spec:
  group: database.ecommerce.com
  names:
    kind: XDatabase                # Developers create "XDatabase" resources
    plural: xdatabases
  versions:
    - name: v1alpha1
      schema:
        openAPIV3Schema:
          properties:
            spec:
              properties:
                parameters:
                  properties:
                    size:
                      type: string
                      enum: [small, medium, large]  # Simple size selector
                    engine:
                      type: string
                      enum: [postgresql]
                    version:
                      type: string
```

#### Composition (How to Fulfill the Request)

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xdatabase-aurora
spec:
  compositeTypeRef:
    apiVersion: database.ecommerce.com/v1alpha1
    kind: XDatabase

  resources:
    - name: rds-cluster
      base:
        apiVersion: rds.aws.upbound.io/v1beta1
        kind: Cluster
        spec:
          forProvider:
            engine: aurora-postgresql
            # Size mapping:
            # small  → db.t4g.medium  (2 vCPU, 4 GB, ~$100/mo)
            # medium → db.r6g.large   (2 vCPU, 16 GB, ~$250/mo)
            # large  → db.r6g.xlarge  (4 vCPU, 32 GB, ~$500/mo)
```

The Composition maps the developer's simple `size: small` parameter to the actual Aurora instance class, VPC subnets, security groups, backup configuration, and encryption settings — all hidden behind a clean API.

---

## 5. Verification Checklist

- [ ] Backstage is running and accessible
- [ ] Template "New Microservice" appears in the Backstage template list
- [ ] Template form renders correctly with all parameters
- [ ] Scaffolding creates a GitHub repository with correct structure
- [ ] Branch protection enabled on the new repository
- [ ] ArgoCD Application created for the new service
- [ ] Service registered in Backstage catalog
- [ ] Crossplane is running: `kubectl get pods -n crossplane-system`
- [ ] XDatabase CRD exists: `kubectl get crd xdatabases.database.ecommerce.com`
- [ ] Database provisioning works: create an XDatabase and verify it becomes Ready
- [ ] All 6 existing services registered in the service catalog
- [ ] Service catalog shows dependencies, APIs, and ownership
- [ ] End-to-end flow: template → repo → deploy → catalog takes < 5 minutes

---

## 6. Troubleshooting

### Backstage template fails at "Publish to GitHub"

```bash
# Check GitHub integration token
# Backstage → Settings → GitHub Integration

# The token needs 'repo' and 'workflow' scopes
# Verify in app-config.yaml:
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
```

### ArgoCD Application not created

```bash
# Check if the ArgoCD plugin is installed in Backstage
# Verify ArgoCD API URL in app-config.yaml

# Check ArgoCD directly
argocd app list | grep <service-name>
```

### Crossplane database stuck in "Creating"

```bash
# Check Crossplane provider status
kubectl get provider.pkg.crossplane.io

# Check the managed resource
kubectl describe cluster.rds.aws.upbound.io <name>

# Common causes:
# 1. AWS credentials not configured
# 2. VPC/subnet selector not matching
# 3. Security group rules blocking access
```

### Catalog entity not showing in Backstage

```bash
# Check catalog-info.yaml location
# Backstage → Catalog → Register existing component

# Verify YAML format
# The apiVersion must be: backstage.io/v1alpha1
# The kind must be: Component
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Backstage vs. Port** | Backstage | Port / Cortex | Open-source, large plugin ecosystem, CNCF project. Trade-off: requires development effort for customization. |
| **Crossplane vs. Terraform** | Crossplane | Terraform Cloud / Atlantis | Kubernetes-native, GitOps-compatible, self-service API. Trade-off: newer, smaller community than Terraform. |
| **Golden paths vs. free-form** | Golden paths (opinionated templates) | Free-form (any stack) | Consistency, faster onboarding, easier operations. Trade-off: less flexibility for edge cases. |
| **Size-based DB selection** | small/medium/large | Custom instance class | Simple for developers, guardrailed by platform team. Trade-off: less flexibility for advanced users. |

---

## 8. Production Considerations

- **Template governance** — Platform team owns and maintains templates; review changes via PR
- **Service maturity scorecards** — Define maturity levels (bronze/silver/gold) based on observability, security, and documentation coverage
- **Tech radar** — Maintain a tech radar in Backstage showing adopted, trial, assessed, and hold technologies
- **Plugin ecosystem** — Add Backstage plugins for PagerDuty (incidents), Grafana (dashboards), Kubecost (costs), and Lighthouse (API quality)
- **Self-service guardrails** — Use Crossplane compositions to enforce security, networking, and compliance requirements in all provisioned infrastructure
- **Documentation** — Use TechDocs (Backstage's built-in docs) to colocate service documentation with the service catalog
- **Adoption metrics** — Track template usage, self-service adoption rate, and mean time to first deploy for new services

---

## 9. Summary

This phase completes the 14-phase DevOps lifecycle. The platform now provides:

| Capability | Phase | Status |
|-----------|-------|--------|
| Version control & commit standards | Phase 1 | Complete |
| 6 microservices | Phase 2 | Complete |
| Production containers | Phase 3 | Complete |
| AWS infrastructure (IaC) | Phase 4 | Complete |
| CI/CD pipelines | Phase 5 | Complete |
| Kubernetes orchestration | Phase 6 | Complete |
| GitOps deployment | Phase 7 | Complete |
| Full observability | Phase 8 | Complete |
| Security & compliance | Phase 9 | Complete |
| Chaos engineering | Phase 10 | Complete |
| Service mesh | Phase 11 | Complete |
| Multi-region DR | Phase 12 | Complete |
| Cost optimization | Phase 13 | Complete |
| Developer platform | Phase 14 | Complete |

**From `git init` to a self-service internal developer platform — the full DevOps lifecycle.**

---

[← Phase 13: FinOps](../phase-13-finops/README.md) | [Back to Project Overview](../README.md)
