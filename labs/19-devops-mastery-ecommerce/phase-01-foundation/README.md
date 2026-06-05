# Phase 1: Project Foundation & Version Control

**Difficulty:** Beginner | **Time:** 2-3 hours | **Prerequisites:** None

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

This phase establishes the project scaffolding, version control strategy, and commit quality standards that every subsequent phase depends on. You will set up:

- **Monorepo structure** — A single repository housing all 6 microservices, infrastructure code, and CI/CD pipelines
- **Trunk-based development** — Short-lived feature branches merging into `main`, enabling rapid integration
- **Conventional commits** — Machine-readable commit messages enforced via commitlint, enabling automated changelogs and semantic versioning
- **Git hooks** — Pre-commit validation via Husky to catch issues before they reach CI

### Where This Fits in the Architecture

```
Phase 1 (You Are Here)
  └── Monorepo scaffolding & commit standards
Phase 2 → Application code (microservices)
Phase 3 → Containerization
Phase 4 → Infrastructure as Code
  ...
Phase 14 → Platform Engineering
```

Every subsequent phase builds on this foundation. Commit conventions set here drive automated versioning in Phase 5 (CI/CD) and changelog generation.

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Git | 2.40+ | `brew install git` |
| Node.js | 20 LTS | `brew install node@20` |
| npm | 10+ | Ships with Node.js |

### Verify Installation

```bash
git --version    # git version 2.40+
node --version   # v20.x.x
npm --version    # 10.x.x
```

---

## 3. Step-by-Step Implementation

### Step 1: Initialize the Monorepo

```bash
mkdir ecommerce-platform && cd ecommerce-platform
git init
```

### Step 2: Create the Directory Structure

```bash
# Service directories
mkdir -p services/{api-gateway,user-service,product-service,order-service,payment-service,notification-service}

# Infrastructure and CI/CD directories (used in later phases)
mkdir -p infrastructure/{modules,environments}
mkdir -p .github/workflows
```

### Step 3: Install Commitlint and Husky

```bash
# Initialize package.json at the repo root
npm init -y

# Install commitlint
npm install --save-dev @commitlint/cli @commitlint/config-conventional

# Install and initialize Husky
npm install --save-dev husky
npx husky init
```

### Step 4: Configure the Commit Message Hook

```bash
# Create the commit-msg hook
echo 'npx --no -- commitlint --edit "$1"' > .husky/commit-msg
chmod +x .husky/commit-msg
```

### Step 5: Create the Commitlint Configuration

Create `.commitlintrc.js` at the repository root (see [Configuration Walkthrough](#4-configuration-walkthrough) for a line-by-line explanation):

```javascript
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [2, 'always', [
      'api-gateway', 'user-service', 'product-service',
      'order-service', 'payment-service', 'notification-service',
      'infra', 'ci', 'docs'
    ]],
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'perf', 'test', 'build', 'ci', 'chore'
    ]]
  }
};
```

### Step 6: Create the Initial Commit

```bash
git add .
git commit -m "chore(infra): initialize monorepo with commitlint and husky"
```

**Expected output:**

```
[main (root-commit) abc1234] chore(infra): initialize monorepo with commitlint and husky
 5 files changed, 42 insertions(+)
```

### Step 7: Test Commit Validation

```bash
# This should FAIL — invalid commit type
git commit --allow-empty -m "updated stuff"
# Expected: ✖ subject may not be empty, type may not be empty

# This should PASS — valid conventional commit
git commit --allow-empty -m "docs(docs): add project README"
# Expected: commit created successfully
```

### Step 8: Set Up Branch Protection (GitHub)

After pushing to GitHub, configure branch protection on `main`:

1. Go to **Settings → Branches → Add rule**
2. Branch name pattern: `main`
3. Enable:
   - Require a pull request before merging
   - Require status checks to pass before merging
   - Require linear history (enforces rebase merges)
   - Do not allow bypassing the above settings

---

## 4. Configuration Walkthrough

### `.commitlintrc.js` — Line by Line

```javascript
// Extend the standard conventional commit rules
// This provides defaults: type(scope): subject format
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // scope-enum: [severity, applicability, allowed-values]
    // severity 2 = error (blocks commit)
    // 'always' = scope must be one of these values
    'scope-enum': [2, 'always', [
      'api-gateway',             // API Gateway service
      'user-service',            // User/Auth service
      'product-service',         // Product catalog service
      'order-service',           // Order management service
      'payment-service',         // Payment processing service
      'notification-service',    // Email/SMS notifications
      'infra',                   // Infrastructure/Terraform changes
      'ci',                      // CI/CD pipeline changes
      'docs'                     // Documentation changes
    ]],

    // type-enum: allowed commit types (Angular convention)
    'type-enum': [2, 'always', [
      'feat',      // New feature
      'fix',       // Bug fix
      'docs',      // Documentation only
      'style',     // Formatting, no logic change
      'refactor',  // Code restructuring, no behavior change
      'perf',      // Performance improvement
      'test',      // Adding or updating tests
      'build',     // Build system or dependencies
      'ci',        // CI/CD configuration
      'chore'      // Maintenance tasks
    ]]
  }
};
```

### Commit Message Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

**Examples:**

```
feat(user-service): add JWT token refresh endpoint
fix(order-service): handle duplicate order submission
ci(ci): add Trivy container scanning to pipeline
docs(docs): update API gateway routing diagram
perf(product-service): add Redis caching for catalog queries
```

### Husky Hook: `.husky/commit-msg`

```bash
npx --no -- commitlint --edit "$1"
```

- `npx --no` — Run commitlint without prompting to install
- `--edit "$1"` — Read the commit message from the file Git provides (`.git/COMMIT_EDITMSG`)
- If commitlint finds violations, the commit is aborted

---

## 5. Verification Checklist

- [ ] `npm test` (if any root-level tests exist) passes
- [ ] Invalid commit messages are rejected:
  ```bash
  git commit --allow-empty -m "bad message"
  # Should fail with commitlint errors
  ```
- [ ] Valid commit messages succeed:
  ```bash
  git commit --allow-empty -m "chore(docs): test commit validation"
  # Should succeed
  ```
- [ ] All 10 commit types are accepted (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`)
- [ ] All 9 scopes are accepted (`api-gateway`, `user-service`, `product-service`, `order-service`, `payment-service`, `notification-service`, `infra`, `ci`, `docs`)
- [ ] Husky hooks run automatically on `git commit` (not just manually)
- [ ] `.commitlintrc.js` is committed and version-controlled

---

## 6. Troubleshooting

### Husky hooks not running

```bash
# Verify Husky is initialized
ls .husky/
# Should contain: commit-msg, _/

# Re-initialize if missing
npx husky init
echo 'npx --no -- commitlint --edit "$1"' > .husky/commit-msg
chmod +x .husky/commit-msg
```

### "commitlint not found" error

```bash
# Ensure devDependencies are installed
npm install

# Verify commitlint is available
npx commitlint --version
```

### Commit hook not triggering after clone

```bash
# Husky requires `npm install` to set up hooks after cloning
npm install
```

### Windows line ending issues

```bash
# Configure Git to handle line endings
git config core.autocrlf input
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Monorepo vs. polyrepo** | Monorepo | Separate repo per service | Atomic changes across services, shared tooling, easier CI path filtering. Trade-off: larger repo size. |
| **Trunk-based vs. Gitflow** | Trunk-based | Gitflow (develop/release branches) | Faster integration, fewer merge conflicts, aligns with CI/CD philosophy. Trade-off: requires strong CI to catch regressions. |
| **Commitlint vs. manual review** | Commitlint (automated) | Manual PR review of messages | Zero human overhead, consistent formatting, enables automated changelogs. Trade-off: learning curve for team. |
| **Husky vs. server-side hooks** | Husky (client-side) | Git server hooks | Faster feedback loop for developers, works offline. Trade-off: can be bypassed with `--no-verify` (mitigated by CI checks). |

---

## 8. Production Considerations

- **CI validation** — Add commitlint as a CI step so commits that bypass local hooks are still caught (implemented in Phase 5)
- **Protected branches** — `main` should require PR reviews and passing CI before merge
- **Signed commits** — Consider requiring GPG-signed commits for audit trails
- **CODEOWNERS** — Add a `CODEOWNERS` file mapping service directories to team owners for automatic PR review assignment
- **Changelog automation** — Tools like `semantic-release` or `conventional-changelog` can generate changelogs from these structured commits (leveraged in Phase 5)

---

## 9. Next Phase

**[Phase 2: Application Development (Microservices) →](../phase-02-microservices/README.md)**

With the monorepo structure and commit standards in place, Phase 2 builds out the 6 microservices that form the e-commerce platform — including API Gateway, User Service, Product Service, Order Service, Payment Service, and Notification Service.

---

[← Back to Project Overview](../README.md) | [Phase 2: Microservices →](../phase-02-microservices/README.md)
