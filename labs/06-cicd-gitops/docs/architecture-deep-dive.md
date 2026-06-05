# Lab 06: CI/CD Pipeline with GitOps — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework + GitOps Principles  
> **Scope:** End-to-end GitOps pipeline — Flask API → GitHub Actions CI → Docker → Trivy → ArgoCD → Kubernetes

---

## What This Pipeline Solves

Manual deployments are the symptom; lack of automation confidence is the disease. Teams deploy manually because they don't trust their automated processes. Building a GitOps pipeline where every deployment is reproducible, tested, scanned, and reversible creates the confidence that enables frequent deployment — and frequent deployment enables faster iteration, faster bug fixes, and faster response to incidents.

---

## Architecture: The Two-Pipeline Model

GitOps splits deployment into two distinct concerns:

**CI (Continuous Integration):** "Is this code correct and safe?" Runs on every push. If any check fails, the pipeline stops — nothing reaches production.

**CD (Continuous Deployment):** "What should be running in the cluster?" ArgoCD answers this by watching Git. When CI succeeds and updates the manifest, ArgoCD syncs the cluster.

The separation is important: CI is a gate. CD is a reconciliation loop. Conflating them (CI directly deploys to the cluster) means there's no single source of truth for cluster state — different CI runs may have deployed different versions without a clear record.

---

## Step-by-Step: CI Pipeline

### Step 1 — Code Quality: Flake8 Linting

```yaml
- name: Lint with flake8
  run: |
    flake8 app/ --max-line-length=100 --extend-ignore=E203
    # E203: whitespace before ':' (conflicts with black formatter)
```

**Why lint before test?**  
Linting is O(seconds); tests are O(minutes). Catching syntax errors and style violations before running the test suite fails fast — a developer who pushed with a typo doesn't wait 5 minutes for tests to run before seeing the error.

**Why `--max-line-length=100` not the PEP8 default of 79?**  
PEP8's 79-character limit was designed for 80-column terminals. Modern editors and code review interfaces handle 100+ characters without wrapping. Enforcing 79 characters leads to awkward line breaks that reduce readability. 100 is a pragmatic compromise between PEP8 and unrestricted line length.

### Step 2 — Unit Tests with pytest

```yaml
- name: Run tests
  run: |
    pytest tests/ -v \
      --cov=app \
      --cov-report=term-missing \
      --cov-fail-under=80  # fail if coverage drops below 80%
```

**Why `--cov-fail-under=80`?**  
Coverage gates prevent the gradual erosion of test coverage over time. Without a minimum, engineers add features without tests, coverage drifts downward, and the test suite provides less confidence in each subsequent deployment. An 80% threshold allows meaningful business logic coverage while not requiring tests for every boilerplate import and constant.

**The Flask health endpoint (required for Kubernetes probes):**

```python
# app/app.py
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'version': os.environ.get('APP_VERSION', 'unknown')
    }), 200

@app.route('/api/items', methods=['GET'])
def get_items():
    return jsonify({'items': []})
```

**Why a dedicated `/health` endpoint?**  
The Kubernetes readiness and liveness probes need a lightweight endpoint that returns 200 when the application is ready. The main API endpoints may require database connections or cache initialization — an unhealthy dependency should fail the health check. A dedicated `/health` endpoint can incorporate dependency checks (`db.ping()`, `cache.ping()`) without side effects.

### Step 3 — Multi-Stage Docker Build

```dockerfile
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Production image
FROM python:3.11-slim AS production

WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ .

# Non-root user
RUN adduser --disabled-password --gecos '' appuser
USER appuser

EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
```

**Why `python:3.11-slim` not `python:3.11-alpine`?**  
Alpine Linux uses musl libc instead of glibc. Many Python packages (NumPy, Pandas, cryptography) have C extensions compiled against glibc — they either won't install on Alpine or require compilation from source (dramatically increasing build time and image size). `slim` is a Debian-based image stripped of unnecessary tools but using glibc — Python packages install without compilation issues.

**Why `gunicorn --workers 2` in CMD?**  
Flask's built-in development server is single-threaded and not designed for production. Gunicorn is a WSGI server that forks worker processes — 2 workers handle 2 concurrent requests. The `2 × CPU + 1` formula for worker count (= 3 for 1 vCPU) is a common starting point; `requests.cpu = 500m` (0.5 vCPU) makes 2 workers correct.

### Step 4 — Trivy Security Scan

```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.IMAGE_NAME }}:${{ github.sha }}
    exit-code: '1'              # fail the pipeline on findings
    ignore-unfixed: true        # skip CVEs with no patch available
    severity: 'CRITICAL,HIGH'   # only alert on serious CVEs
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Trivy scan results to GitHub Security tab
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

**Why `ignore-unfixed: true`?**  
Unfixed CVEs have no available patch. Blocking a deployment because of a CVE with no fix forces developers to either ship vulnerable code or block the entire pipeline indefinitely. Trivy's `ignore-unfixed` flag filters these out — the team is alerted to unfixed CVEs in the SARIF report but the pipeline continues. Blocking deployment on unfixed CVEs trains teams to ignore security alerts entirely.

**Why upload SARIF to GitHub Security tab?**  
SARIF (Static Analysis Results Interchange Format) allows CVE findings to appear in GitHub's Security tab as code scanning alerts. Security engineers can triage findings, dismiss false positives, and track remediation directly in GitHub — without accessing a separate security dashboard.

---

## Step-by-Step: CD with ArgoCD

### Step 5 — Kubernetes Deployment Manifest (3 Replicas)

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cicd-app
  labels:
    app: cicd-app
spec:
  replicas: 3   # ← 3 for AZ-spread HA; CI updates image tag here
  selector:
    matchLabels:
      app: cicd-app
  template:
    spec:
      containers:
        - name: cicd-app
          image: ghcr.io/owner/cicd-app:latest   # replaced by CI with git SHA
          
          ports:
            - containerPort: 5000
          
          env:
            - name: APP_VERSION
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['version']
          
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          
          readinessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 10
            periodSeconds: 5
          
          livenessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 30
            periodSeconds: 15
```

**Why 3 replicas in this lab (vs 2 in lab 05)?**  
This lab explicitly demonstrates HA patterns. With 3 replicas across 3 AZs:
- 1 replica during rolling update (1 being replaced, 1 being added) = 2 available = 67% capacity
- With 2 replicas: 1 available during update = 50% capacity — borderline for many workloads

3 replicas also allows a PodDisruptionBudget of `minAvailable: 2`, ensuring at least 2 pods are always available during voluntary disruptions (node drains, cluster upgrades).

### Step 6 — ArgoCD Application Definition

```yaml
# k8s/argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cicd-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io  # clean up cluster resources on app deletion
spec:
  project: default
  
  source:
    repoURL: https://github.com/owner/cicd-gitops
    targetRevision: HEAD
    path: k8s/
  
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - RespectIgnoreDifferences=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**Why `retry` with exponential backoff?**  
Transient failures (API server briefly unavailable, resource not yet ready) should not permanently fail a sync. The retry with exponential backoff (`5s → 10s → 20s`) handles transient issues without hammering the API server. `limit: 3` prevents infinite retry loops for persistent failures.

**Why `finalizers: resources-finalizer.argocd.argoproj.io`?**  
Without this finalizer, deleting the ArgoCD Application resource leaves all the Kubernetes resources (Deployments, Services, etc.) orphaned in the cluster. The finalizer tells ArgoCD: "before you delete this Application, delete all the resources it manages." This prevents silent resource leaks.

### Step 7 — Full Pipeline Execution

```
git push origin main
    │
    ▼
GitHub Actions: Lint (10s) → Tests (30s) → Docker build (90s) → Trivy scan (60s)
    │
    ▼ (all pass)
Push image to registry with SHA tag
    │
    ▼
Update k8s/deployment.yaml: sed "image: app:abc1234"
git commit && git push
    │
    ▼
ArgoCD polls repository (or receives webhook: <1s delay)
ArgoCD diffs current cluster vs. Git
    │
    ▼
ArgoCD applies: kubectl apply -f k8s/
Kubernetes rolling update: 1 new pod → health check passes → 1 old pod terminated
Repeat × replicas
    │
    ▼
Pipeline complete: ~5 minutes total from push to running
```

**Total pipeline time: ~5 minutes**
- Lint: 10s
- Tests: 30s
- Docker build: 90s
- Trivy scan: 60s
- ECR push: 30s
- Manifest update + ArgoCD sync: 30s
- Rolling update: 90s

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **5-minute deployment cycle:** From commit to production in 5 minutes — fast feedback for developers
- **SARIF security reports:** Security findings tracked in GitHub, not a separate tool — same interface as code review
- **`SRE-Project2-Summary.md`:** Detailed troubleshooting log documenting every error encountered — institutional knowledge preserved

### Security
- **SARIF upload to GitHub:** Security findings visible to all engineers, not hidden in a CI log
- **`ignore-unfixed: true`:** Pipeline blocks on patchable CVEs, doesn't block on unfixable ones — actionable alerts only
- **Non-root container:** Flask app runs as `appuser`, not `root`

### Reliability
- **3 replicas across 3 AZs:** Single AZ failure maintains 2/3 capacity
- **`selfHeal: true`:** ArgoCD reverts manual cluster changes — drift is impossible
- **Health endpoint:** Kubernetes probes use a dedicated health endpoint, not the main API

### Performance Efficiency
- **Gunicorn 2 workers:** Production-grade WSGI server handles concurrent requests
- **slim base image:** ~100MB vs ~1GB full image — faster pull times in CI and at deploy

### Cost Optimization
- **k3d (local cluster):** Development uses k3d rather than a cloud cluster — no compute cost for development and testing
- **Layer caching in Docker build:** `COPY requirements.txt` before `COPY app/` means the pip install layer is cached unless `requirements.txt` changes — builds are faster and cheaper

### Sustainability
- **Multi-stage build:** Smaller production image = less storage, less bandwidth, less compute for image scanning

---

## Key Architectural Insight

The key design insight of this pipeline is **GitOps as a contract**: the Git repository is a legal contract between the development team and the cluster. The cluster is obligated to run exactly what Git says, and ArgoCD enforces this obligation continuously. This contract eliminates the "configuration archaeology" problem — figuring out what's actually running in production by looking at logs, talking to the person who last deployed, or reading undocumented shell scripts. What's in Git is what's running. The operational model becomes: to change what's running, change Git.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
