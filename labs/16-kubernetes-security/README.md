# Lab 16: Kubernetes Security — RBAC, Network Policies & Vault

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Vault](https://img.shields.io/badge/Vault-FFEC6E?style=flat&logo=vault&logoColor=black)
![Falco](https://img.shields.io/badge/Falco-00AEC7?style=flat&logo=falco&logoColor=white)
![OPA](https://img.shields.io/badge/OPA-7D9AAA?style=flat&logo=openpolicyagent&logoColor=white)

## Summary (The "Elevator Pitch")

Implemented end-to-end Kubernetes security: RBAC for access control, NetworkPolicies for zero-trust networking, Trivy for image vulnerability scanning, Falco for runtime threat detection, OPA for policy enforcement, CIS benchmark compliance, and HashiCorp Vault for secrets management. This is the security posture that production Kubernetes clusters need.

## The Problem

The Kubernetes cluster had **default settings** — every pod could talk to every other pod, all users had cluster-admin, secrets were stored as base64 (not encrypted), container images were never scanned, and there was no runtime threat detection. One compromised pod could access the entire cluster.

## The Solution

Implemented **defense in depth** across 6 layers: **RBAC** restricts who can do what (namespace-scoped roles), **NetworkPolicies** restrict pod-to-pod communication (deny-all by default), **Trivy** scans images for CVEs, **Falco** detects suspicious runtime activity (shell in container, unexpected network connections), **OPA** enforces admission policies (no privileged containers, no latest tags), and **Vault** manages secrets with dynamic credentials and automatic rotation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  Kubernetes Security Layers                      │
│                                                                  │
│  Layer 1: RBAC                Layer 2: Network Policies          │
│  ┌───────────────────┐       ┌───────────────────────┐          │
│  │ cluster-admin     │       │ default-deny-all      │          │
│  │ namespace-admin   │       │ allow frontend→backend│          │
│  │ developer (read)  │       │ allow backend→database│          │
│  │ monitoring (read) │       │ allow monitoring→all  │          │
│  └───────────────────┘       └───────────────────────┘          │
│                                                                  │
│  Layer 3: Image Scanning     Layer 4: Runtime Security          │
│  ┌───────────────────┐       ┌───────────────────────┐          │
│  │ Trivy Operator    │       │ Falco                 │          │
│  │ (scan on deploy)  │       │ (detect shell access) │          │
│  └───────────────────┘       │ (detect crypto mining)│          │
│                              └───────────────────────┘          │
│  Layer 5: Policy Enforcement Layer 6: Secrets Management        │
│  ┌───────────────────┐       ┌───────────────────────┐          │
│  │ OPA Gatekeeper    │       │ HashiCorp Vault       │          │
│  │ (no privileged)   │       │ (dynamic secrets)     │          │
│  │ (no :latest tag)  │       │ (auto-rotation)       │          │
│  └───────────────────┘       └───────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| RBAC | Access control (who can do what) | Built into Kubernetes, namespace-scoped |
| NetworkPolicy | Pod-to-pod traffic control | Zero-trust networking at the pod level |
| Trivy Operator | Continuous image vulnerability scanning | Auto-scans new deployments, detailed CVE reports |
| Falco | Runtime threat detection | Detects suspicious syscalls (shell access, file changes) |
| OPA Gatekeeper | Admission policy enforcement | Blocks non-compliant resources before they're created |
| HashiCorp Vault | Secrets management | Dynamic secrets, auto-rotation, audit logging |
| CIS Benchmarks | Compliance validation | Industry-standard Kubernetes security checklist |

## Implementation Steps

### Step 1: Implement RBAC
**What this does:** Creates role-based access — cluster admins get full access, namespace admins manage their namespace, developers get read-only, monitoring tools get specific permissions.
```bash
kubectl apply -f rbac/cluster-roles.yaml
kubectl apply -f rbac/namespace-roles.yaml
```

### Step 2: Apply Network Policies
**What this does:** Default-deny-all blocks all traffic, then explicit allow rules open only necessary paths (frontend → backend → database).
```bash
kubectl apply -f network-policies/default-deny.yaml
kubectl apply -f network-policies/namespace-isolation.yaml
kubectl apply -f network-policies/app-policies.yaml
kubectl apply -f network-policies/monitoring-access.yaml
```

### Step 3: Deploy Trivy Operator
**What this does:** Installs Trivy as a Kubernetes operator that automatically scans every new container image for known vulnerabilities (CVEs).
```bash
kubectl apply -f scanning/trivy-operator.yaml
kubectl get vulnerabilityreports -A   # View scan results
```

### Step 4: Deploy Falco
**What this does:** Installs Falco for runtime security — detects shell access to containers, unexpected network connections, privilege escalation, and file system modifications.
```bash
kubectl apply -f scanning/falco-rules.yaml
```

### Step 5: Configure OPA Gatekeeper
**What this does:** Installs policy templates and constraints — blocks privileged containers, requires resource limits, prevents :latest image tags, enforces read-only root filesystem.
```bash
kubectl apply -f scanning/opa-policies/templates.yaml
kubectl apply -f scanning/opa-policies/constraints.yaml
```

### Step 6: Install HashiCorp Vault
**What this does:** Deploys Vault for secrets management with Kubernetes authentication — pods authenticate with their service account and receive dynamic, short-lived credentials.
```bash
kubectl apply -f vault/vault-install.yaml
./scripts/setup-vault.sh
kubectl apply -f vault/vault-k8s-auth.yaml
```

### Step 7: Run CIS Benchmark
**What this does:** Validates the cluster against CIS Kubernetes Benchmark — checks API server configuration, etcd encryption, kubelet settings, and network policies.
```bash
kubectl apply -f compliance/cis-benchmark.yaml
```

### Step 8: Run Security Audit
**What this does:** Comprehensive security audit script that checks RBAC, network policies, image scanning results, Falco alerts, and compliance status.
```bash
./scripts/security-audit.sh
./scripts/compliance-report.sh
```

## Project Structure

```
16-kubernetes-security/
├── README.md
├── rbac/
│   ├── cluster-roles.yaml           # Cluster-wide roles (admin, viewer)
│   └── namespace-roles.yaml         # Namespace-scoped roles (dev, ops, monitor)
├── network-policies/
│   ├── default-deny.yaml            # Deny all ingress/egress by default
│   ├── namespace-isolation.yaml     # Isolate namespaces from each other
│   ├── app-policies.yaml            # Allow specific service-to-service traffic
│   └── monitoring-access.yaml       # Allow Prometheus to scrape all namespaces
├── scanning/
│   ├── trivy-operator.yaml          # Trivy vulnerability scanner deployment
│   ├── falco-rules.yaml            # Falco runtime security rules
│   └── opa-policies/
│       ├── templates.yaml           # OPA constraint templates
│       └── constraints.yaml         # Active policy constraints
├── compliance/
│   ├── cis-benchmark.yaml           # CIS Kubernetes Benchmark validation
│   └── pod-security-standards.yaml  # Pod Security Standards enforcement
├── vault/
│   ├── vault-install.yaml           # Vault Helm deployment values
│   ├── vault-policies.hcl           # Vault access policies
│   └── vault-k8s-auth.yaml         # Kubernetes auth method configuration
└── scripts/
    ├── security-audit.sh            # Full security audit script
    ├── setup-vault.sh               # Vault initialization and unsealing
    └── compliance-report.sh         # Generate compliance report
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `rbac/namespace-roles.yaml` | Creates dev, ops, and monitor roles scoped to specific namespaces | Least privilege, RBAC |
| `network-policies/default-deny.yaml` | Blocks all ingress and egress traffic — explicit allows required | Zero-trust networking |
| `scanning/falco-rules.yaml` | Detects: shell in container, crypto mining, privilege escalation | Runtime security, syscall monitoring |
| `scanning/opa-policies/constraints.yaml` | Blocks: privileged containers, :latest tags, missing resource limits | Admission control, policy as code |
| `vault/vault-k8s-auth.yaml` | Enables pods to authenticate to Vault using their ServiceAccount | Dynamic secrets, identity-based access |

## Results & Metrics

| Security Layer | Before | After |
|---------------|--------|-------|
| Access Control | Everyone is cluster-admin | RBAC with namespace-scoped roles |
| Network | All pods can talk to all pods | Zero-trust with default-deny |
| Image Scanning | None | Trivy scans every deployment |
| Runtime Detection | None | Falco alerts on suspicious activity |
| Policy Enforcement | None | OPA blocks non-compliant resources |
| Secrets | Base64 in K8s secrets | Vault with dynamic credentials |
| Compliance | Unknown | CIS Benchmark compliant |

## How I'd Explain This in an Interview

> "The Kubernetes cluster had default settings — every pod could talk to every other pod, everyone was cluster-admin, and secrets were just base64-encoded. I implemented defense in depth across 6 layers: RBAC for access control, NetworkPolicies for zero-trust networking (deny-all by default), Trivy for image scanning, Falco for runtime threat detection (alerts if someone gets a shell in a container), OPA Gatekeeper to block privileged containers before they're created, and HashiCorp Vault for dynamic secrets with automatic rotation. The key principle is defense in depth — no single layer is enough, but together they make compromise significantly harder."

## Key Concepts Demonstrated

- **Defense in Depth** — 6 security layers working together
- **RBAC** — Namespace-scoped access control with least privilege
- **Zero-Trust Networking** — Default-deny NetworkPolicies
- **Image Scanning** — Trivy catches CVEs before deployment
- **Runtime Security** — Falco detects threats in running containers
- **Policy as Code** — OPA Gatekeeper enforces standards
- **Secrets Management** — Vault dynamic secrets with auto-rotation
- **CIS Benchmarks** — Industry-standard compliance validation

## Lessons Learned

1. **Default-deny NetworkPolicies break things** — apply allow rules before deny rules, or services can't communicate
2. **Falco generates noise initially** — tune rules to your environment before enabling alerting
3. **OPA catches misconfigurations early** — blocking :latest tags prevents "it works on my machine" issues
4. **Vault needs careful initialization** — unseal keys must be stored securely (not in Git!)
5. **RBAC is not just for humans** — service accounts also need least-privilege roles

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
