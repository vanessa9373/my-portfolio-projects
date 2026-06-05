# K8S-06: Helm Chart Development

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)
![YAML](https://img.shields.io/badge/YAML-Templates-orange?style=for-the-badge)
![CI/CD](https://img.shields.io/badge/CI%2FCD-Chart_Publishing-green?style=for-the-badge)

## Summary (The "Elevator Pitch")

Helm charts eliminate YAML duplication across environments by parameterizing Kubernetes manifests into reusable, version-controlled packages. This lab builds a production-grade Helm chart from scratch -- with environment-specific values files, reusable template helpers, lifecycle hooks for database migrations, sub-chart dependencies for PostgreSQL, and automated chart testing -- demonstrating the full Helm development workflow from `helm create` to chart publishing.

## The Problem

The platform team manages a microservice deployed across three environments: dev, staging, and production. Each environment has 15+ Kubernetes manifests (Deployments, Services, ConfigMaps, Ingresses, etc.) with minor differences -- different replica counts, resource limits, image tags, and ingress hostnames. With 50+ YAML files maintained by hand, configuration drift is constant: staging has a resource limit that was updated in prod but never backported, dev is missing an environment variable added to staging three weeks ago. Every deployment is a copy-paste exercise with a find-and-replace step that occasionally misses a value, causing outages from misconfigured environment variables or missing volume mounts.

## The Solution

We author a Helm chart that parameterizes all environment-specific values into a single `values.yaml` with per-environment overrides (`values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml`). Shared template logic lives in `_helpers.tpl` to eliminate duplication of labels and naming conventions. A pre-upgrade hook runs database migrations before the new application version starts receiving traffic. PostgreSQL is added as a sub-chart dependency rather than maintaining separate database manifests. The chart includes `helm test` hooks for post-deployment verification and passes `helm lint` for CI integration. The result is one chart, three values files, zero drift.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Helm Chart: myapp                           │
│                                                                 │
│  values.yaml ──────┐                                            │
│  values-dev.yaml ──┤                                            │
│  values-staging.yaml┤──► Template Engine ──► Rendered Manifests │
│  values-prod.yaml ──┘         │                    │            │
│                               │                    ▼            │
│  _helpers.tpl ────────────────┘         ┌──────────────────┐   │
│  (shared labels,                        │   Deployment     │   │
│   naming, selectors)                    │   Service        │   │
│                                         │   Ingress        │   │
│                                         │   ConfigMap      │   │
│                                         └──────────────────┘   │
│                                                                 │
│  ┌─────────────────┐    ┌───────────────────────────────────┐  │
│  │  Hooks           │    │  Sub-Charts                       │  │
│  │                  │    │                                   │  │
│  │  pre-upgrade:    │    │  postgresql (Bitnami)             │  │
│  │   db-migration   │    │  - StatefulSet                    │  │
│  │   Job            │    │  - Service                        │  │
│  │                  │    │  - PVC                            │  │
│  └─────────────────┘    └───────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────┐                                           │
│  │  Tests           │                                           │
│  │  test-connection │                                           │
│  │  (helm test)     │                                           │
│  └─────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|---|---|---|
| Helm 3 | Kubernetes package manager | Industry standard for templating and managing K8s applications |
| Go Templates | Template language for manifests | Built into Helm, supports conditionals, loops, and functions |
| _helpers.tpl | Reusable template functions | DRY principle for labels, names, and selectors across templates |
| Helm Hooks | Lifecycle event handlers | Run database migrations before new code deploys (pre-upgrade) |
| Sub-charts | Dependency management | Include PostgreSQL without maintaining database manifests |
| helm lint | Static analysis | Catches template errors and best practice violations in CI |
| helm test | Post-deploy verification | Validates the release is functional after installation |

## Implementation Steps

### Step 1: Scaffold Chart with `helm create`

```bash
helm create charts/myapp
ls charts/myapp/
# Chart.yaml  charts/  templates/  values.yaml
```

**What this does:** Generates a complete chart scaffold with standard directory structure, default templates for Deployment/Service/Ingress, a values.yaml with sensible defaults, and a _helpers.tpl with common template functions. This is the starting point that we customize.

### Step 2: Customize Templates (Deployment, Service, Ingress)

```bash
# Review and customize the generated templates
cat charts/myapp/templates/deployment.yaml
cat charts/myapp/templates/service.yaml
cat charts/myapp/templates/ingress.yaml

# Lint to verify templates render correctly
helm lint charts/myapp/
```

**What this does:** Modifies the scaffolded templates to match our application requirements -- adding environment variables from ConfigMaps, health check probes, resource limits driven by values, and Ingress annotations for the ingress controller. The `helm lint` command validates that all templates render without errors.

### Step 3: Create _helpers.tpl with Reusable Template Functions

```bash
cat charts/myapp/templates/_helpers.tpl
# Defines: myapp.name, myapp.fullname, myapp.labels, myapp.selectorLabels
```

**What this does:** Defines named templates that are reused across all manifest files. `myapp.fullname` generates a consistent resource name, `myapp.labels` produces the standard label set (app, chart, release, version), and `myapp.selectorLabels` provides the minimal labels for selector matching. This ensures label consistency and eliminates copy-paste errors.

### Step 4: Add Values for Dev, Staging, and Prod

```bash
# Compare environment-specific overrides
diff charts/myapp/values-dev.yaml charts/myapp/values-prod.yaml

# Render templates with dev values to inspect output
helm template myapp charts/myapp/ -f charts/myapp/values-dev.yaml

# Render templates with prod values to compare
helm template myapp charts/myapp/ -f charts/myapp/values-prod.yaml
```

**What this does:** Creates environment-specific values files that override the base `values.yaml`. Dev uses 1 replica with minimal resources, staging uses 2 replicas to test HA, and prod uses 3 replicas with higher resource limits and autoscaling enabled. The `helm template` command renders manifests locally without deploying, useful for reviewing what will be applied.

### Step 5: Add Pre-Upgrade Hook for Database Migrations

```bash
# View the migration hook template
cat charts/myapp/templates/hooks/pre-upgrade-migration.yaml

# Install the chart and trigger a hook
helm install myapp charts/myapp/ -f charts/myapp/values-dev.yaml
helm upgrade myapp charts/myapp/ -f charts/myapp/values-dev.yaml --set image.tag=v2.0.0

# Watch the migration job run before the deployment updates
kubectl get jobs -w
```

**What this does:** The pre-upgrade hook creates a Kubernetes Job that runs database migrations before the new application version deploys. The hook has a `hook-delete-policy: before-hook-creation` annotation so previous migration jobs are cleaned up. If the migration fails, the upgrade is aborted and the old version keeps running.

### Step 6: Add PostgreSQL as Sub-Chart Dependency

```bash
# Add Bitnami PostgreSQL as a dependency
cat charts/myapp/Chart.yaml  # shows dependencies section

# Download the dependency
helm dependency update charts/myapp/

# Verify the sub-chart is pulled
ls charts/myapp/charts/
# postgresql-*.tgz
```

**What this does:** Declares PostgreSQL as a chart dependency in `Chart.yaml` and pulls the Bitnami chart into `charts/`. The sub-chart's values are configured under the `postgresql:` key in our values.yaml, giving us a managed database without writing any database manifests ourselves.

### Step 7: Write Helm Tests

```bash
# Run helm tests after deployment
helm test myapp

# View test results
kubectl get pods -l "app.kubernetes.io/instance=myapp" --show-all
kubectl logs myapp-test-connection
```

**What this does:** Runs the test-connection pod defined in `templates/tests/test-connection.yaml`. The test pod makes an HTTP request to the application Service and exits with code 0 on success. This validates that the Service is routing traffic to the Deployment correctly after install or upgrade.

### Step 8: Package and Publish Chart

```bash
# Package the chart into a .tgz archive
helm package charts/myapp/ --version 1.0.0

# Push to an OCI-compatible registry
helm push myapp-1.0.0.tgz oci://registry.example.com/charts

# Or index for a chart repository
helm repo index . --url https://charts.example.com/
```

**What this does:** Packages the chart directory into a versioned tarball for distribution. The chart can be pushed to an OCI registry (ECR, ACR, Harbor) or a traditional chart repository (ChartMuseum, GitHub Pages). Consumers install with `helm install myapp oci://registry.example.com/charts/myapp --version 1.0.0`.

## Project Structure

```
K8S-06-helm-chart-development/
├── README.md
├── charts/
│   └── myapp/
│       ├── Chart.yaml                          # Chart metadata and dependencies
│       ├── values.yaml                         # Default values (base)
│       ├── values-dev.yaml                     # Dev environment overrides
│       ├── values-staging.yaml                 # Staging environment overrides
│       ├── values-prod.yaml                    # Production environment overrides
│       └── templates/
│           ├── _helpers.tpl                    # Reusable template functions
│           ├── deployment.yaml                 # Application Deployment
│           ├── service.yaml                    # ClusterIP Service
│           ├── ingress.yaml                    # Ingress resource
│           ├── hooks/
│           │   └── pre-upgrade-migration.yaml  # DB migration Job hook
│           └── tests/
│               └── test-connection.yaml        # Helm test pod
└── scripts/
    ├── deploy.sh                               # Install/upgrade helper
    └── cleanup.sh                              # Uninstall helper
```

## Key Files Explained

| File | What It Does | Key Concepts |
|---|---|---|
| `Chart.yaml` | Defines chart name, version, appVersion, and dependencies | Semantic versioning, sub-chart declarations |
| `values.yaml` | Base configuration with all parameterized values | Hierarchical YAML structure, sensible defaults |
| `values-prod.yaml` | Production overrides (3 replicas, higher resources) | Environment-specific configuration, value merging |
| `_helpers.tpl` | Named templates for labels, names, selectors | Go template `define`/`include`, DRY principle |
| `deployment.yaml` | Templated Deployment with values-driven config | `{{ .Values }}` references, conditionals, range loops |
| `pre-upgrade-migration.yaml` | Job that runs DB migrations before upgrade | Helm hooks, hook-weight, hook-delete-policy |
| `test-connection.yaml` | Pod that validates Service connectivity | `helm.sh/hook: test`, post-deploy validation |

## Results & Metrics

| Metric | Before (Raw YAML) | After (Helm Chart) |
|---|---|---|
| Files per environment | 15+ manifest files x 3 envs = 45+ | 7 templates + 3 values files = 10 |
| Configuration drift incidents | 2-3 per month | 0 (single source of truth) |
| Deploy command complexity | 5+ kubectl apply commands | `helm upgrade --install -f values-<env>.yaml` |
| Rollback time | 15+ min (find old YAML, re-apply) | `helm rollback myapp` (~10 seconds) |
| Migration safety | Manual, error-prone | Automated pre-upgrade hook with abort on failure |
| Environment setup time | 2-3 hours (copy/modify all YAML) | 10 minutes (create new values file) |
| Template validation | None (errors found at deploy time) | `helm lint` + `helm template` in CI pipeline |

## How I'd Explain This in an Interview

> "We had 45+ YAML files across three environments with constant configuration drift -- staging would be missing a resource limit that prod had, dev would have a stale environment variable. I built a Helm chart that parameterizes everything into template files with environment-specific values overrides. The base values.yaml has defaults, and values-dev.yaml, values-staging.yaml, and values-prod.yaml only override what differs. I added a pre-upgrade hook that runs database migrations as a Kubernetes Job before the new code deploys -- if migrations fail, the upgrade aborts automatically. PostgreSQL is a sub-chart dependency so we don't maintain separate database manifests. The result was going from 45+ files with drift to 10 files with zero drift, and deployments went from a multi-step kubectl process to a single helm upgrade command."

## Key Concepts Demonstrated

- **Helm Chart Structure** -- Standard directory layout (Chart.yaml, values.yaml, templates/) that packages Kubernetes manifests as a reusable, versioned artifact
- **Go Templating** -- Template language using `{{ .Values.x }}`, conditionals (`{{ if }}`), and loops (`{{ range }}`) to generate dynamic YAML
- **_helpers.tpl** -- Named template definitions (`{{ define }}` / `{{ include }}`) that centralize reusable logic like label generation
- **Values Hierarchy** -- Base values.yaml merged with environment-specific overrides, following Helm's last-value-wins merge strategy
- **Helm Hooks** -- Annotations that trigger Jobs or other resources at specific lifecycle points (pre-install, pre-upgrade, post-delete)
- **Sub-Chart Dependencies** -- Declaring other charts as dependencies in Chart.yaml, with their values nested under the dependency name
- **helm lint** -- Static analysis tool that validates chart structure, template rendering, and best practices without deploying
- **helm test** -- Post-deployment verification using test-annotated pods that validate the release is functional

## Lessons Learned

1. **Values schema validation catches errors early** -- Adding a `values.schema.json` file makes `helm lint` validate the structure and types of values, catching typos like `replcia: 3` before they reach the cluster.
2. **Hook-delete-policy is essential for idempotency** -- Without `before-hook-creation` delete policy, old migration Jobs linger and block subsequent upgrades because Job names collide. Always set a delete policy.
3. **Named templates in _helpers.tpl prevent label drift** -- Defining labels once in a named template and including it everywhere ensures Deployments, Services, and Ingresses always have matching selectors. Manual label copying is the number one cause of "Service has no endpoints" errors.
4. **helm template is your best debugging tool** -- Rendering templates locally with `helm template` before deploying reveals exactly what manifests Helm will apply. Pipe the output to `kubectl apply --dry-run=server` for server-side validation.
5. **Sub-chart values scoping is counterintuitive** -- PostgreSQL sub-chart values must be nested under `postgresql:` in the parent values.yaml. Flat keys like `postgresqlPassword` at the root level are silently ignored, which caused a confusing "authentication failed" error during initial setup.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
