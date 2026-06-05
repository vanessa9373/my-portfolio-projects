# Phase 3: Containerization

**Difficulty:** Beginner | **Time:** 3-4 hours | **Prerequisites:** Phase 2

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

This phase transforms the development Docker images from Phase 2 into production-grade containers. The Dockerfile uses best practices that achieve:

- **80% smaller images** — Multi-stage builds discard build tools from the final image
- **Zero root containers** — Non-root execution via distroless base images
- **Built-in health checks** — HTTP probes for container orchestrators
- **Fast builds** — Layer caching optimized for dependency-first, code-second builds

### Before and After

| Metric | Dev Image (Phase 2) | Production Image (Phase 3) |
|--------|---------------------|---------------------------|
| Base image | `node:20` | `gcr.io/distroless/nodejs20-debian12` |
| Image size | ~1 GB | ~180 MB |
| Running as | root | nonroot |
| Shell access | Yes | No (distroless) |
| Health check | None | HTTP probe every 30s |
| Attack surface | Large (apt, bash, etc.) | Minimal (Node.js runtime only) |

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Docker | 24+ | `brew install --cask docker` |
| Node.js | 20 LTS | Installed in Phase 2 |

### Verify Installation

```bash
docker --version      # Docker version 24+
docker buildx version # buildx v0.11+
```

---

## 3. Step-by-Step Implementation

### Step 1: Create the Multi-Stage Dockerfile

Create `Dockerfile` at the root of each service directory. The template below is for Node.js services (API Gateway, User Service, Order Service, Payment Service):

```dockerfile
# Multi-stage Dockerfile — Node.js microservice
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Stage 2: Production (distroless)
FROM gcr.io/distroless/nodejs20-debian12
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json .

EXPOSE 3000

USER nonroot

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/health', (r) => { process.exit(r.statusCode === 200 ? 0 : 1) })"]

CMD ["dist/server.js"]
```

### Step 2: Build the Image

```bash
docker build -t user-service:latest services/user-service/

# Expected output (final lines):
# => exporting to image
# => => naming to docker.io/library/user-service:latest
```

### Step 3: Verify Image Size

```bash
docker images user-service:latest
```

**Expected output:**

```
REPOSITORY      TAG       IMAGE ID       CREATED         SIZE
user-service    latest    abc123def456   10 seconds ago   178MB
```

Compare with a standard Node.js image (~1 GB) — this is approximately 80% smaller.

### Step 4: Run and Test the Container

```bash
# Run the container
docker run -d --name user-service-test \
  -p 3001:3000 \
  -e NODE_ENV=production \
  -e DATABASE_URL=postgresql://app:password@host.docker.internal:5432/users \
  user-service:latest

# Test the health endpoint
curl http://localhost:3001/health
# Expected: {"status":"ok"}

# Verify running as non-root
docker exec user-service-test whoami 2>/dev/null || echo "No shell (distroless) — expected"

# Check the health status via Docker
docker inspect --format='{{.State.Health.Status}}' user-service-test
# Expected: healthy (after start-period)
```

### Step 5: Verify Non-Root Execution

```bash
# Check the user ID of the running process
docker top user-service-test

# Expected: UID 65534 (nonroot), not UID 0 (root)
```

### Step 6: Create a `.dockerignore` File

```bash
cat > services/user-service/.dockerignore << 'EOF'
node_modules
npm-debug.log
.git
.gitignore
.env
coverage
tests
*.md
Dockerfile
docker-compose*.yml
EOF
```

This prevents unnecessary files from being sent to the Docker build context, speeding up builds.

### Step 7: Test Layer Caching

```bash
# First build (cold cache) — slower
time docker build -t user-service:v1 services/user-service/

# Change only source code (not dependencies)
# Second build — should be fast because package*.json hasn't changed
time docker build -t user-service:v2 services/user-service/

# The COPY package*.json and npm ci layers should show "CACHED"
```

---

## 4. Configuration Walkthrough

### `Dockerfile` — Line by Line

```dockerfile
# ──────────────────────────────────────────────────────────
# STAGE 1: Build
# ──────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
# Alpine variant is ~50MB vs ~350MB for full node:20
# Named "builder" so Stage 2 can reference artifacts

WORKDIR /app
# All subsequent commands run in /app

COPY package*.json ./
# Copy ONLY dependency manifests first
# This creates a cache layer — if dependencies don't change,
# Docker skips the npm ci step on subsequent builds

RUN npm ci --only=production
# npm ci = clean install from lockfile (deterministic)
# --only=production = skip devDependencies (smaller node_modules)

COPY . .
# Now copy the application source code
# This layer busts cache only when source changes, not on dependency changes

RUN npm run build
# Compile TypeScript to JavaScript in /app/dist

# ──────────────────────────────────────────────────────────
# STAGE 2: Production
# ──────────────────────────────────────────────────────────
FROM gcr.io/distroless/nodejs20-debian12
# Google's distroless image: contains ONLY the Node.js runtime
# No shell (bash), no package manager (apt), no utilities
# Dramatically reduces CVE surface area

WORKDIR /app

COPY --from=builder /app/dist ./dist
# Copy only the compiled output from Stage 1

COPY --from=builder /app/node_modules ./node_modules
# Copy production dependencies

COPY --from=builder /app/package.json .
# Copy package.json for metadata

EXPOSE 3000
# Document the port (doesn't actually publish it)

USER nonroot
# Run as UID 65534 (nonroot user built into distroless)
# Prevents container escape attacks from gaining root

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/health', (r) => { process.exit(r.statusCode === 200 ? 0 : 1) })"]
# --interval=30s    — Check every 30 seconds
# --timeout=3s      — Fail if no response in 3 seconds
# --start-period=10s — Give the app 10s to start before checking
# --retries=3       — Mark unhealthy after 3 consecutive failures
# Uses Node.js inline script (no curl/wget in distroless)

CMD ["dist/server.js"]
# Start the compiled server (distroless uses exec form only)
```

---

## 5. Verification Checklist

- [ ] Image builds successfully: `docker build -t user-service:test services/user-service/`
- [ ] Image size is under 200 MB: `docker images user-service:test --format '{{.Size}}'`
- [ ] Container starts and responds: `curl http://localhost:3001/health`
- [ ] Container runs as non-root: `docker top <container-id>` shows UID 65534
- [ ] Health check passes: `docker inspect --format='{{.State.Health.Status}}' <container-id>` returns `healthy`
- [ ] No shell access (distroless): `docker exec <container-id> sh` fails
- [ ] Layer caching works: second build with only source changes reuses `npm ci` layer
- [ ] `.dockerignore` excludes `node_modules`, `.git`, and test files

---

## 6. Troubleshooting

### Build fails: "npm run build" command not found

```bash
# Ensure package.json has a "build" script
# For TypeScript projects:
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js"
  }
}
```

### Container exits immediately

```bash
# Check container logs
docker logs <container-id>

# Common causes:
# 1. Missing environment variables (DATABASE_URL, etc.)
# 2. Cannot connect to external services
# 3. Port already in use inside the container
```

### Health check always unhealthy

```bash
# Wait for start-period (10s) to elapse
# Check if the health endpoint responds:
docker exec <container-id> node -e "require('http').get('http://localhost:3000/health', (r) => console.log(r.statusCode))"

# If this fails, the app may not be listening on port 3000
```

### "Permission denied" in distroless container

```bash
# Distroless nonroot user has UID 65534
# Ensure file permissions allow this user to read app files
# In the builder stage, files are created as root — this is fine
# because COPY --from=builder preserves the file content, not ownership
```

### Python service Dockerfile differences

For the Product Service and Notification Service (Python/FastAPI), use a Python distroless base:

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

FROM gcr.io/distroless/python3-debian12
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /app .
ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages
EXPOSE 8000
USER nonroot
CMD ["main.py"]
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Distroless vs. Alpine** | Distroless | Alpine Linux | Smaller attack surface — no shell, no package manager. Trade-off: harder to debug (no `sh`, `curl`). |
| **Multi-stage vs. single stage** | Multi-stage | Single `FROM` | Build tools (npm, tsc) aren't in production image. Trade-off: slightly more complex Dockerfile. |
| **npm ci vs. npm install** | `npm ci` | `npm install` | Deterministic installs from lockfile, faster in CI. Trade-off: requires `package-lock.json` to exist. |
| **HEALTHCHECK in Dockerfile** | Included | Kubernetes probes only | Provides health monitoring even in Docker Compose. Trade-off: Kubernetes probes override this. |
| **Non-root user** | `USER nonroot` | Default (root) | Prevents privilege escalation. Trade-off: some operations may fail if they require root (but shouldn't). |

---

## 8. Production Considerations

- **Image scanning** — Scan images with Trivy before deployment (implemented in Phase 5)
- **Image registry** — Push to Amazon ECR (implemented in Phase 5 CI pipeline)
- **Image tagging** — Use Git SHA tags (`user-service:abc123`) not `latest` for traceability
- **Build caching** — Use Docker BuildKit layer caching in CI to speed up builds
- **Base image updates** — Monitor distroless image updates for security patches
- **Resource limits** — Set `--memory` and `--cpus` flags when running containers (enforced in Phase 6 via Kubernetes)
- **Debug containers** — In production, use ephemeral debug containers (`kubectl debug`) instead of shelling into distroless

---

## 9. Next Phase

**[Phase 4: Infrastructure as Code →](../phase-04-infrastructure-as-code/README.md)**

With production-ready container images, Phase 4 provisions the AWS infrastructure to host them — VPC with 3 Availability Zones, EKS with Bottlerocket nodes, Aurora PostgreSQL, and ElastiCache Redis, all managed via Terraform modules.

---

[← Phase 2: Microservices](../phase-02-microservices/README.md) | [Back to Project Overview](../README.md) | [Phase 4: Infrastructure as Code →](../phase-04-infrastructure-as-code/README.md)
