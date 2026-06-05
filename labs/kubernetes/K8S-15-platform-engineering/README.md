# K8S-15: Platform Engineering with Backstage & Crossplane

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Backstage](https://img.shields.io/badge/Backstage-9BF0E1?style=for-the-badge&logo=backstage&logoColor=black)
![Crossplane](https://img.shields.io/badge/Crossplane-FF6F61?style=for-the-badge&logo=crossplane&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)
![Platform Engineering](https://img.shields.io/badge/Platform_Engineering-4A90D9?style=for-the-badge)

## Summary (The "Elevator Pitch")

This lab builds an internal developer platform using Backstage as a developer portal and Crossplane for self-service infrastructure provisioning via Kubernetes CRDs. Developers request databases, caches, and storage through a portal instead of filing tickets, reducing provisioning time from days to minutes while enforcing organizational standards through Golden Path templates.

## The Problem

A growing engineering organization has 12 development teams, each filing Jira tickets every time they need infrastructure: a PostgreSQL database, a Redis cache, an S3 bucket. The platform team of 3 engineers is the bottleneck — average provisioning time is 4.5 days. Developers have started spinning up untracked resources in personal AWS accounts (shadow IT), creating security and cost blind spots. There is no standardization: teams use different Terraform modules, different naming conventions, and different security configurations. The platform team spends 80% of their time on repetitive provisioning instead of building tooling.

## The Solution

An internal developer platform built on two pillars: Backstage as the developer portal providing a software catalog and Golden Path templates, and Crossplane as the infrastructure control plane enabling self-service provisioning through Kubernetes custom resources. Developers browse the software catalog, select a Golden Path template, fill in parameters, and Crossplane provisions fully-compliant infrastructure in minutes. Every resource is tracked, tagged, and follows organizational standards automatically.

## Architecture

```
                        +---------------------------+
                        |     Developer Portal      |
                        |       (Backstage)         |
                        |  +---------------------+  |
                        |  | Software Catalog    |  |
                        |  | Golden Path Templ.  |  |
                        |  | TechDocs            |  |
                        +--+----------+----------+--+
                                      |
                           kubectl apply (CRDs)
                                      |
                        +-------------v-------------+
                        |   Kubernetes Cluster       |
                        |  +---------------------+   |
                        |  |    Crossplane        |   |
                        |  |  +-----------+       |   |
                        |  |  | XRDs      |       |   |
                        |  |  | Compos.   |       |   |
                        |  |  | Providers |       |   |
                        |  +--+-----+-----+-------+  |
                        +------------|----------------+
                                     |
                    +----------------+----------------+
                    |                |                 |
              +-----v-----+  +------v------+  +------v------+
              |  AWS RDS   |  | ElastiCache |  |   AWS S3    |
              | PostgreSQL |  |   (Redis)   |  |   Bucket    |
              |            |  |             |  |             |
              | + Security |  | + Security  |  | + Bucket    |
              |   Group    |  |   Group     |  |   Policy    |
              | + Subnet   |  | + Subnet    |  | + Encryption|
              |   Group    |  |   Group     |  |             |
              +------------+  +-------------+  +-------------+
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| Backstage | Developer portal and software catalog | CNCF project, extensible plugin architecture, industry standard for platform engineering |
| Crossplane | Infrastructure-as-code via Kubernetes CRDs | Enables GitOps for infrastructure, leverages K8s reconciliation loop, no new tooling for devs |
| AWS Provider | Crossplane provider for AWS resources | Maps K8s custom resources to AWS API calls, supports 900+ resource types |
| PostgreSQL (RDS) | Managed database provisioned via Crossplane | Common developer request, demonstrates full lifecycle management |
| Helm | Package management for Backstage and Crossplane | Standard K8s deployment method, simplifies complex installations |
| Golden Path Templates | Standardized project scaffolding | Enforces best practices, reduces cognitive load, ensures compliance |

## Implementation Steps

### Step 1: Deploy Backstage Developer Portal

```bash
# Create namespace for Backstage
kubectl create namespace backstage

# Add Backstage Helm repository
helm repo add backstage https://backstage.github.io/charts
helm repo update

# Deploy Backstage with custom configuration
helm install backstage backstage/backstage \
  --namespace backstage \
  --values manifests/backstage-values.yaml \
  --wait --timeout 300s

# Verify Backstage is running
kubectl get pods -n backstage
kubectl get svc -n backstage
```

**What this does:** Deploys the Backstage developer portal into a dedicated namespace. Backstage serves as the single pane of glass where developers discover services, read documentation, and provision infrastructure through Golden Path templates.

### Step 2: Configure Software Catalog

```bash
# Apply the software catalog configuration
kubectl apply -f manifests/backstage-deployment.yaml

# Register catalog entities
# Backstage reads catalog-info.yaml files from Git repositories
# The catalog tracks all services, APIs, resources, and teams

# Verify catalog is populated
curl -s http://backstage.local/api/catalog/entities | jq '.[] | .metadata.name'
```

**What this does:** Configures the Backstage Software Catalog to discover and track all services, APIs, and infrastructure resources across the organization. The catalog provides a single source of truth for what the organization builds and operates.

### Step 3: Install Crossplane with AWS Provider

```bash
# Install Crossplane using Helm
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

kubectl create namespace crossplane-system

helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --set args='{"--enable-composition-revisions"}' \
  --wait --timeout 300s

# Install the AWS provider
kubectl apply -f crossplane/provider-aws.yaml

# Wait for provider to become healthy
kubectl wait --for=condition=healthy provider.pkg.crossplane.io/provider-aws \
  --timeout=300s

# Configure AWS credentials
kubectl create secret generic aws-creds \
  -n crossplane-system \
  --from-file=creds=./aws-credentials.txt

kubectl apply -f crossplane/provider-config.yaml
```

**What this does:** Installs Crossplane as the infrastructure control plane inside Kubernetes. The AWS provider teaches Crossplane how to manage AWS resources. Credentials are stored as a Kubernetes secret and referenced by the provider configuration.

### Step 4: Create CompositeResourceDefinition (XRD) for Database

```bash
# Apply the XRD that defines the "Database" abstraction
kubectl apply -f crossplane/xrd-database.yaml

# Verify the XRD is established
kubectl get xrd
kubectl get crd | grep database

# The XRD creates a new API endpoint in Kubernetes:
# databases.platform.example.com
```

**What this does:** Creates a CompositeResourceDefinition that defines a new Kubernetes API type called "Database." This abstraction hides the complexity of AWS RDS, security groups, and subnet groups behind a simple interface with parameters like engine, size, and storage.

### Step 5: Create Composition (Maps XRD to AWS Resources)

```bash
# Apply the Composition that maps the Database XRD to AWS resources
kubectl apply -f crossplane/composition-aws-rds.yaml

# Verify the Composition is ready
kubectl get composition
kubectl describe composition database-aws-rds

# The Composition defines: XRD "Database" = RDS Instance + Security Group + Subnet Group
```

**What this does:** Creates a Composition that defines how the abstract "Database" resource maps to concrete AWS resources. When a developer requests a Database, Crossplane automatically provisions an RDS instance, security group, and DB subnet group with organizational defaults for encryption, backup, and tagging.

### Step 6: Build Golden Path Template in Backstage

```bash
# Register the Golden Path template with Backstage
# Templates are defined as YAML and stored in Git

# The template defines:
# 1. Input parameters (service name, team, database size)
# 2. Scaffolding steps (generate repo, add manifests)
# 3. Output actions (create GitHub repo, open PR)

# Apply template registration to catalog
kubectl apply -f manifests/backstage-deployment.yaml

# Verify template appears in Backstage UI
curl -s http://backstage.local/api/catalog/entities?filter=kind=template | \
  jq '.[] | .metadata.name'
```

**What this does:** Registers Golden Path templates in Backstage that guide developers through creating new services with all required infrastructure. The template scaffolds a repository with Kubernetes manifests, Crossplane claims, CI/CD pipelines, and documentation — enforcing organizational standards automatically.

### Step 7: Test Self-Service — Developer Requests Database via Portal

```bash
# Developer creates a database claim through the portal
# This is what Backstage submits on behalf of the developer:
kubectl apply -f crossplane/claim-database.yaml

# Watch Crossplane provision the resources
kubectl get database.platform.example.com -w

# Check the underlying AWS resources being created
kubectl get managed -l crossplane.io/claim-name=team-alpha-db

# Verify the RDS instance is available
kubectl get rdsinstance.database.aws.crossplane.io

# Get the connection details (stored as a K8s Secret)
kubectl get secret team-alpha-db-conn -o jsonpath='{.data.endpoint}' | base64 -d
```

**What this does:** Demonstrates the full self-service workflow. A developer selects "Request Database" in Backstage, fills in parameters (team name, size, engine), and Crossplane provisions a fully-configured RDS instance with security group, subnet group, encryption, and backups — all within minutes instead of days.

## Project Structure

```
K8S-15-platform-engineering/
├── README.md
├── manifests/
│   └── backstage-deployment.yaml
├── crossplane/
│   ├── provider-aws.yaml
│   ├── xrd-database.yaml
│   ├── composition-aws-rds.yaml
│   └── claim-database.yaml
└── scripts/
    ├── deploy.sh
    ├── install-crossplane.sh
    └── cleanup.sh
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `manifests/backstage-deployment.yaml` | Deploys Backstage portal with catalog and template configuration | Developer portal, software catalog, service discovery |
| `crossplane/provider-aws.yaml` | Installs and configures the AWS provider for Crossplane | Provider packages, credential management, reconciliation |
| `crossplane/xrd-database.yaml` | Defines the abstract "Database" API (CompositeResourceDefinition) | Platform APIs, abstraction layers, schema validation |
| `crossplane/composition-aws-rds.yaml` | Maps the Database abstraction to concrete AWS resources | Compositions, resource mapping, patch-and-transform |
| `crossplane/claim-database.yaml` | Example developer claim requesting a database | Self-service claims, namespace-scoped resources |
| `scripts/deploy.sh` | End-to-end deployment automation | Bootstrap script, dependency ordering |
| `scripts/install-crossplane.sh` | Installs Crossplane and AWS provider | Helm deployment, provider lifecycle |
| `scripts/cleanup.sh` | Tears down all platform components | Graceful deletion, resource ordering |

## Results & Metrics

| Metric | Before | After |
|---|---|---|
| Infrastructure provisioning time | 4.5 days (ticket-based) | 12 minutes (self-service) |
| Platform team ticket volume | 45 tickets/week | 5 tickets/week (edge cases only) |
| Shadow IT instances | 23 untracked resources | 0 (all via platform) |
| Configuration drift | 67% of resources non-compliant | 0% (compositions enforce standards) |
| Developer satisfaction (survey) | 2.1/5 | 4.6/5 |
| Time to onboard new service | 2 weeks | 30 minutes (Golden Path) |

## How I'd Explain This in an Interview

> "We had 12 teams filing tickets for every database and cache they needed — our 3-person platform team was spending 80% of their time on repetitive provisioning. I built an internal developer platform using Backstage as the portal and Crossplane as the infrastructure engine. Developers now go to the portal, pick a Golden Path template, and Crossplane provisions fully-compliant AWS resources through Kubernetes CRDs. Provisioning went from 4.5 days to 12 minutes, shadow IT dropped to zero, and every resource automatically gets encryption, backups, and proper tagging. The key insight was using Kubernetes as the control plane for infrastructure — developers already know kubectl, so there's no new tooling to learn."

## Key Concepts Demonstrated

- **Platform Engineering** — Building an internal developer platform that provides self-service capabilities with guardrails, reducing cognitive load while enforcing standards
- **Crossplane Compositions** — Abstracting complex multi-resource infrastructure behind simple Kubernetes CRDs, enabling self-service without exposing cloud complexity
- **Golden Path Templates** — Opinionated, pre-built templates that guide developers toward the recommended way to build and deploy services
- **Software Catalog** — A centralized registry of all software assets (services, APIs, resources, teams) providing organizational visibility
- **Infrastructure as Kubernetes CRDs** — Extending Kubernetes to manage cloud resources, leveraging its reconciliation loop for infrastructure drift detection
- **Platform APIs** — Defining organizational abstractions (XRDs) that hide cloud-specific details behind a stable, versioned API

## Lessons Learned

1. **Start with one Golden Path, not ten** — We initially tried to template everything at once. Focusing on the most common request (PostgreSQL database) first let us iterate on the developer experience before scaling to other resource types.
2. **Compositions need versioning from day one** — When we updated a Composition, existing resources were affected. Using CompositionRevisions from the start would have prevented breaking changes to running infrastructure.
3. **Developer experience trumps technical elegance** — Our first XRD had 30 parameters for maximum flexibility. Developers wanted 5 parameters with sensible defaults. Reducing the API surface increased adoption from 20% to 95%.
4. **Backstage plugin ecosystem is powerful but immature** — Some community plugins had breaking changes between versions. Pinning plugin versions and having integration tests saved us multiple times during upgrades.
5. **Platform teams need product thinking** — Treating the developer platform as a product (with user research, feedback loops, and SLOs) was the mindset shift that made the platform successful. Building features nobody asked for wasted months of effort.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
