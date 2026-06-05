# Phase 5: CI/CD Pipelines

**Difficulty:** Intermediate | **Time:** 5-7 hours | **Prerequisites:** Phase 4

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
9. [Next Phase](#9-next-phase)

---

## 1. Overview

This phase creates monorepo-aware CI/CD pipelines using GitHub Actions. The pipelines are optimized for the 6-service architecture:

- **CI Pipeline** — Automatically detects which services changed, runs lint/test/build/scan in parallel per service
- **CD Pipeline** — Promotes builds through staging → production with environment gates
- **Version Bumping** — Automated semantic versioning based on conventional commits (from Phase 1)
- **Release Automation** — Tag-based releases with changelog generation

### Pipeline Architecture

```
Push/PR to main
      │
      ▼
┌─────────────┐
│ Detect      │ ← Path filters: which services changed?
│ Changes     │
└──────┬──────┘
       │ services: [user-service, order-service]
       ▼
┌──────────────────────────────────┐
│        Per-Service Matrix        │
│  ┌────────┐  ┌────────┐        │
│  │  Lint  │  │  Lint  │        │
│  └───┬────┘  └───┬────┘        │
│  ┌───┴────┐  ┌───┴────┐        │
│  │  Test  │  │  Test  │        │  ← Parallel
│  └───┬────┘  └───┬────┘        │
│  ┌───┴────┐  ┌───┴────┐        │
│  │ Build  │  │ Build  │        │
│  │ + Scan │  │ + Scan │        │  ← Trivy (CRITICAL/HIGH)
│  └───┬────┘  └───┬────┘        │
│  ┌───┴────┐  ┌───┴────┐        │
│  │Push ECR│  │Push ECR│        │  ← Only on main branch
│  └────────┘  └────────┘        │
└──────────────────────────────────┘
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| GitHub CLI | 2.x | `brew install gh` |
| Docker | 24+ | Installed in Phase 3 |
| AWS CLI | 2.x | Installed in Phase 4 |
| Node.js | 20 LTS | Installed in Phase 2 |

### GitHub Setup

```bash
# Authenticate with GitHub
gh auth login

# Required repository secrets (set in GitHub Settings → Secrets):
# - AWS_ROLE_ARN: IAM role for OIDC-based authentication
# - CODECOV_TOKEN: (optional) for code coverage reports
```

### AWS OIDC Setup (one-time)

```bash
# Create OIDC identity provider for GitHub Actions (no static credentials)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

---

## 3. Step-by-Step Implementation

### Step 1: Create the CI Pipeline

Create `.github/workflows/ci.yml` (see [Configuration Walkthrough](#4-configuration-walkthrough) for details):

```bash
mkdir -p .github/workflows
```

The CI pipeline has 3 jobs that run per changed service:
1. **detect-changes** — Uses `dorny/paths-filter` to identify which service directories were modified
2. **lint** — Runs ESLint/flake8 on changed services
3. **test** — Runs unit tests with PostgreSQL and Redis service containers
4. **build-and-scan** — Builds Docker images, scans with Trivy, pushes to ECR

### Step 2: Create the CD Pipeline

Create `.github/workflows/cd.yml`:

The CD pipeline triggers after CI completes on the main branch and:
1. Updates the GitOps repository with new image tags
2. Promotes through environment gates (staging → production approval)
3. Sends deployment notifications

### Step 3: Create Version Bump Script

```bash
mkdir -p scripts
```

Create `scripts/version-bump.sh`:

```bash
#!/bin/bash
# Semantic version bump based on conventional commits
# Usage: ./scripts/version-bump.sh <service-name>

SERVICE=$1
CURRENT_VERSION=$(cat services/$SERVICE/package.json | jq -r '.version')

# Determine bump type from commit messages
if git log --oneline --since="last tag" -- services/$SERVICE/ | grep -q "^.*feat"; then
  BUMP_TYPE="minor"
elif git log --oneline --since="last tag" -- services/$SERVICE/ | grep -q "^.*fix"; then
  BUMP_TYPE="patch"
else
  echo "No version bump needed"
  exit 0
fi

# Bump version
NEW_VERSION=$(npx semver $CURRENT_VERSION -i $BUMP_TYPE)
echo "Bumping $SERVICE from $CURRENT_VERSION to $NEW_VERSION ($BUMP_TYPE)"

# Update package.json
cd services/$SERVICE
npm version $NEW_VERSION --no-git-tag-version
```

Make it executable:

```bash
chmod +x scripts/version-bump.sh
```

### Step 4: Create Release Script

Create `scripts/release.sh`:

```bash
#!/bin/bash
# Release orchestration script
# Usage: ./scripts/release.sh <service-name> <version>

SERVICE=$1
VERSION=$2

echo "Releasing $SERVICE v$VERSION"

# Tag the release
git tag "${SERVICE}/v${VERSION}"
git push origin "${SERVICE}/v${VERSION}"

# Generate changelog from conventional commits
echo "## ${SERVICE} v${VERSION}" > CHANGELOG.md
git log --oneline "$(git describe --tags --abbrev=0 HEAD~1)..HEAD" \
  -- "services/${SERVICE}/" >> CHANGELOG.md

echo "Release ${SERVICE}/v${VERSION} created successfully"
```

Make it executable:

```bash
chmod +x scripts/release.sh
```

### Step 5: Test the CI Pipeline Locally

```bash
# Verify path filtering logic by checking which services have changes
git diff --name-only main | grep "^services/" | cut -d/ -f2 | sort -u

# Run lint locally (same as CI does)
cd services/user-service && npm run lint

# Run tests locally (same as CI does)
cd services/user-service && npm test -- --coverage

# Build and scan locally (same as CI does)
docker build -t user-service:test services/user-service/
docker run --rm aquasec/trivy image user-service:test --severity CRITICAL,HIGH
```

---

## 4. Configuration Walkthrough

### `workflows/ci.yml` — Section by Section

#### Trigger Configuration

```yaml
name: CI Pipeline
on:
  push:
    branches: [main]        # Run on pushes to main
  pull_request:
    branches: [main]        # Run on PRs targeting main

permissions:
  contents: read            # Read repository files
  id-token: write           # Required for OIDC AWS authentication
```

#### Job 1: Detect Changes

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.filter.outputs.changes }}  # Pass changed services to matrix
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |                    # Map directory paths to service names
            api-gateway: 'services/api-gateway/**'
            user-service: 'services/user-service/**'
            product-service: 'services/product-service/**'
            order-service: 'services/order-service/**'
            payment-service: 'services/payment-service/**'
            notification-service: 'services/notification-service/**'
```

If only `services/user-service/` changed, only `user-service` jobs run — other services are skipped entirely. This keeps CI fast even in a monorepo.

#### Job 2: Lint (per service)

```yaml
  lint:
    needs: detect-changes
    if: needs.detect-changes.outputs.services != '[]'   # Skip if no services changed
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}  # Dynamic matrix
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: services/${{ matrix.service }}/package-lock.json
      - run: cd services/${{ matrix.service }} && npm ci && npm run lint
```

#### Job 3: Test (per service, with databases)

```yaml
  test:
    needs: detect-changes
    if: needs.detect-changes.outputs.services != '[]'
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
    runs-on: ubuntu-latest
    services:                           # Spin up databases alongside tests
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports: ["5432:5432"]
      redis:
        image: redis:7-alpine
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: cd services/${{ matrix.service }} && npm ci && npm test -- --coverage
      - uses: codecov/codecov-action@v3        # Upload coverage reports
        with:
          directory: services/${{ matrix.service }}/coverage
```

#### Job 4: Build, Scan, Push (main branch only)

```yaml
  build-and-scan:
    needs: [lint, test]                       # Run after lint and test pass
    if: github.ref == 'refs/heads/main'       # Only on main branch (not PRs)
    strategy:
      matrix:
        service: ${{ fromJson(needs.detect-changes.outputs.services) }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}  # OIDC auth — no static keys
          aws-region: us-east-1

      - uses: aws-actions/amazon-ecr-login@v2
        id: ecr

      - name: Build Docker image
        run: |
          docker build -t ${{ steps.ecr.outputs.registry }}/${{ matrix.service }}:${{ github.sha }} \
            services/${{ matrix.service }}

      - name: Scan with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ steps.ecr.outputs.registry }}/${{ matrix.service }}:${{ github.sha }}
          format: table
          exit-code: 1                        # Fail the build if vulnerabilities found
          severity: CRITICAL,HIGH             # Only block on CRITICAL and HIGH

      - name: Push to ECR
        run: |
          docker push ${{ steps.ecr.outputs.registry }}/${{ matrix.service }}:${{ github.sha }}
```

Key points:
- **OIDC authentication** — No AWS access keys stored in GitHub. The pipeline assumes an IAM role via OIDC federation.
- **Trivy scanning** — Blocks deployment if CRITICAL or HIGH CVEs are found in the container image.
- **Git SHA tagging** — Each image is tagged with the commit SHA for full traceability.

---

## 5. Verification Checklist

- [ ] CI triggers on push to main: check GitHub Actions tab
- [ ] CI triggers on pull request: create a test PR
- [ ] Path filtering works: changing only `user-service/` runs only `user-service` jobs
- [ ] Lint job catches formatting issues
- [ ] Test job runs with PostgreSQL and Redis service containers
- [ ] Test job uploads code coverage to Codecov
- [ ] Build job creates Docker image tagged with Git SHA
- [ ] Trivy scan blocks builds with CRITICAL/HIGH vulnerabilities
- [ ] ECR push succeeds on main branch (not on PRs)
- [ ] OIDC authentication works (no static AWS credentials)
- [ ] `scripts/version-bump.sh` correctly bumps versions
- [ ] `scripts/release.sh` creates Git tags

---

## 6. Troubleshooting

### OIDC authentication fails: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

```bash
# Verify the IAM role's trust policy includes GitHub Actions
aws iam get-role --role-name github-actions-role --query 'Role.AssumeRolePolicyDocument'

# The trust policy must include:
# - Principal: arn:aws:iam::AWS_ACCOUNT:oidc-provider/token.actions.githubusercontent.com
# - Condition: StringEquals token.actions.githubusercontent.com:sub: repo:ORG/REPO:ref:refs/heads/main
```

### Trivy scan fails: image has CRITICAL vulnerabilities

```bash
# Run Trivy locally to see the full report
docker run --rm aquasec/trivy image user-service:latest

# Fix by updating base image or dependencies:
# 1. Update the distroless base image in Dockerfile
# 2. Run npm audit fix in the service directory
# 3. Rebuild and rescan
```

### Path filter reports no changes

```bash
# Verify the filter patterns match your directory structure
# The patterns are relative to the repository root:
# 'services/api-gateway/**' matches services/api-gateway/src/index.js
```

### ECR push fails: "no basic auth credentials"

```bash
# Verify ECR login step completed successfully
# Check that the AWS_ROLE_ARN secret is set in GitHub repository settings
# Verify the IAM role has ecr:GetAuthorizationToken and ecr:PutImage permissions
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Path filtering** | `dorny/paths-filter` | Nx / Turborepo | Lightweight, no additional tooling. Trade-off: doesn't handle transitive dependencies. |
| **OIDC vs. static credentials** | OIDC federation | AWS access keys in secrets | No credential rotation needed, follows AWS best practices. Trade-off: more complex initial setup. |
| **Trivy vs. Snyk** | Trivy | Snyk / Grype | Free, open-source, fast. Trade-off: Snyk has better fix suggestions. |
| **Git SHA tags vs. semver** | Git SHA | Semantic versioning tags | Every commit is traceable. Trade-off: less human-readable. Semver is handled by release scripts separately. |
| **GitHub Actions vs. Jenkins** | GitHub Actions | Jenkins / GitLab CI | Native GitHub integration, managed infrastructure. Trade-off: vendor lock-in to GitHub. |

---

## 8. Production Considerations

- **Branch protection** — Require CI to pass before merging PRs
- **Required reviewers** — At least 1-2 reviewers for PR approval
- **Dependency caching** — npm cache is configured to speed up installs
- **Concurrency groups** — Add concurrency limits to prevent duplicate pipeline runs
- **Secrets scanning** — Add GitHub secret scanning or gitleaks to prevent credential leaks
- **Pipeline notifications** — Send Slack notifications on build failures
- **Artifact retention** — Configure retention policies for build artifacts and test reports
- **Matrix fail-fast** — Set `fail-fast: false` in matrix strategy to see all failures, not just the first

---

## 9. Next Phase

**[Phase 6: Kubernetes Orchestration →](../phase-06-kubernetes/README.md)**

With CI/CD pushing images to ECR, Phase 6 creates Helm charts to deploy the microservices on the EKS cluster — including Horizontal Pod Autoscalers, Pod Disruption Budgets, and health probes.

---

[← Phase 4: Infrastructure as Code](../phase-04-infrastructure-as-code/README.md) | [Back to Project Overview](../README.md) | [Phase 6: Kubernetes Orchestration →](../phase-06-kubernetes/README.md)
