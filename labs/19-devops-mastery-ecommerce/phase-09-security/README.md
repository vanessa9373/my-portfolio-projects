# Phase 9: Security & Compliance

**Difficulty:** Advanced | **Time:** 6-8 hours | **Prerequisites:** Phase 8

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

This phase implements defense-in-depth security across the platform. Every layer has controls — from admission policies that prevent misconfigured workloads from deploying, to network policies that enforce zero-trust communication, to Vault for dynamic secret management.

### Security Layers

```
┌──────────────────────────────────────────────────────────────┐
│                      Security Layers                         │
│                                                              │
│  1. Admission Control (Gatekeeper)                          │
│     └── Block non-root violations before pods are created    │
│                                                              │
│  2. Secret Management (Vault)                               │
│     └── Dynamic credentials, auto-rotation, audit logging    │
│                                                              │
│  3. Network Security (Network Policies)                     │
│     └── Zero-trust: deny all, allow explicit paths only      │
│                                                              │
│  4. Container Security (Phase 3 + Phase 5)                  │
│     └── Distroless images, non-root, Trivy scanning          │
│                                                              │
│  5. Runtime Security (Falco)                                │
│     └── Detect anomalous behavior at runtime                 │
│                                                              │
│  6. Service Mesh Security (Phase 11)                        │
│     └── mTLS between all services                            │
└──────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
phase-09-security/
├── gatekeeper/
│   └── require-nonroot.yaml      # ConstraintTemplate + Constraint
├── vault/
│   ├── vault-config.hcl          # Vault server configuration
│   └── policies/
│       └── ecommerce-app.hcl     # Application access policies
└── network-policies/
    └── user-service.yaml          # Zero-trust network policy
```

---

## 2. Prerequisites

### Tools

| Tool | Version | Install |
|------|---------|---------|
| Helm | 3.13+ | Installed in Phase 6 |
| kubectl | 1.28+ | Installed in Phase 4 |
| vault | 1.15+ | `brew install vault` |

### Install Gatekeeper

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace
```

### Install Vault

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3
```

---

## 3. Step-by-Step Implementation

### Step 1: Deploy the Non-Root Constraint

Apply the Gatekeeper ConstraintTemplate and Constraint:

```bash
kubectl apply -f gatekeeper/require-nonroot.yaml
```

Test that it works:

```bash
# This should be REJECTED — runs as root
kubectl run test-root --image=nginx --restart=Never -n production

# Expected: Error from server (Forbidden): admission webhook "validation.gatekeeper.sh"
# denied the request: Container 'test-root' must not run as root

# This should be ACCEPTED — runs as non-root
kubectl run test-nonroot --image=nginx --restart=Never -n production \
  --overrides='{"spec":{"containers":[{"name":"test-nonroot","image":"nginx","securityContext":{"runAsNonRoot":true,"runAsUser":1000}}]}}'
```

### Step 2: Configure Vault Server

The Vault configuration (`vault/vault-config.hcl`) defines the server's storage backend, TLS listener, auto-unseal, and audit logging. Apply it:

```bash
# Initialize Vault
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 -key-threshold=3

# Save the unseal keys and root token securely
# With KMS auto-unseal configured, manual unseal is only needed for initial setup
```

### Step 3: Create Vault Policies

Apply the application policy that grants microservices access to their secrets:

```bash
# Login to Vault
vault login <ROOT_TOKEN>

# Write the policy
vault policy write ecommerce-app vault/policies/ecommerce-app.hcl

# Enable the Kubernetes auth method
vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"
```

### Step 4: Configure Kubernetes Auth for Each Service

```bash
# Create a role for the user-service
vault write auth/kubernetes/role/user-service \
  bound_service_account_names=user-service \
  bound_service_account_namespaces=production \
  policies=ecommerce-app \
  ttl=1h

# Store a secret
vault kv put secret/ecommerce/user-service \
  database-url="postgresql://app:ROTATED_PASS@aurora-endpoint:5432/users" \
  redis-url="redis://elasticache-endpoint:6379"
```

### Step 5: Deploy Network Policies

Apply the zero-trust network policy for the User Service:

```bash
kubectl apply -f network-policies/user-service.yaml
```

Create similar policies for each service, allowing only the traffic paths they need.

### Step 6: Verify Network Isolation

```bash
# Test allowed path: API Gateway → User Service (should succeed)
kubectl exec -n production deploy/api-gateway -- \
  curl -sf http://user-service:3001/health

# Test blocked path: Order Service → User Service DB (should fail/timeout)
kubectl exec -n production deploy/order-service -- \
  timeout 5 curl -sf http://postgres-users:5432 || echo "Blocked as expected"
```

---

## 4. Configuration Walkthrough

### `gatekeeper/require-nonroot.yaml` — Section by Section

#### ConstraintTemplate (the rule definition)

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirenonroot
spec:
  crd:
    spec:
      names:
        kind: K8sRequireNonRoot       # Name used when creating constraints
      validation:
        openAPIV3Schema:
          type: object
          properties:
            exemptImages:              # Allow specific images to bypass the check
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |                          # Rego policy language (OPA)
        package k8srequirenonroot

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not is_exempt(container.image)     # Skip exempt images
          has_root_access(container)          # Check if running as root
          msg := sprintf("Container '%v' must not run as root", [container.name])
        }

        has_root_access(container) {
          not container.securityContext.runAsNonRoot    # runAsNonRoot not set
        }

        has_root_access(container) {
          container.securityContext.runAsUser == 0      # Explicitly set to root UID
        }

        is_exempt(image) {
          exempt := input.parameters.exemptImages[_]
          glob.match(exempt, [], image)                 # Glob pattern matching
        }
```

#### Constraint (applying the rule)

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireNonRoot
metadata:
  name: require-non-root-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: ["production", "staging"]   # Only enforce in these namespaces
  parameters:
    exemptImages:
      - "istio/proxyv2:*"                   # Istio sidecar needs root for iptables
      - "docker.io/istio/proxyv2:*"         # Both image registries
```

### `vault/vault-config.hcl` — Key Sections

#### Consul Storage Backend

```hcl
storage "consul" {
  address      = "consul.ecommerce.internal:8500"
  scheme       = "https"
  path         = "vault/"
  # Consul provides HA — multiple Vault nodes can use the same backend
  # Only one node is active (leader); others are standby
  consistency_mode = "strong"          # Strong consistency for secret reads
  max_parallel     = 128               # Concurrent requests to Consul
}
```

#### TLS Listener

```hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false                # NEVER disable in production
  tls_cert_file = "/etc/vault/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault/tls/vault-key.pem"
  tls_min_version = "tls13"           # TLS 1.3 minimum — no legacy protocols
}
```

#### KMS Auto-Unseal

```hcl
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = ""  # Populated via VAULT_AWSKMS_SEAL_KEY_ID env var
  # Eliminates manual unseal key management
  # Vault auto-unseals on restart using the KMS key
}
```

#### Dual Audit Logging

```hcl
audit "file" "primary" {
  path = "/var/log/vault/audit.log"
  options = {
    format = "json"                    # Structured logging for SIEM ingestion
    log_raw = false                    # HMAC-hash sensitive values
    hmac_accessor = true               # Hash accessor tokens
    mode = "0600"                      # Restrict file permissions
  }
}

audit "file" "secondary" {
  path = "/var/log/vault/audit-secondary.log"
  # Redundancy: Vault blocks ALL requests if ALL audit devices fail
  # Two audit devices ensure requests continue if one volume fills up
}
```

### `network-policies/user-service.yaml` — Zero-Trust Design

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: user-service
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: user-service               # Apply to User Service pods

  policyTypes:
    - Ingress                          # Control incoming traffic
    - Egress                           # Control outgoing traffic

  ingress:
    # Allow traffic FROM API Gateway only
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - port: 3001
          protocol: TCP

    # Allow Prometheus scraping
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - port: 9090
          protocol: TCP

  egress:
    # Allow DNS resolution
    - to:
        - namespaceSelector: {}
      ports:
        - port: 53
          protocol: UDP

    # Allow PostgreSQL access
    - to:
        - ipBlock:
            cidr: 10.0.0.0/16         # VPC CIDR (Aurora endpoint)
      ports:
        - port: 5432
          protocol: TCP

    # Allow Redis access
    - to:
        - ipBlock:
            cidr: 10.0.0.0/16
      ports:
        - port: 6379
          protocol: TCP

    # Allow RabbitMQ access
    - to:
        - ipBlock:
            cidr: 10.0.0.0/16
      ports:
        - port: 5672
          protocol: TCP
```

---

## 5. Verification Checklist

- [ ] Gatekeeper is running: `kubectl get pods -n gatekeeper-system`
- [ ] ConstraintTemplate applied: `kubectl get constrainttemplate k8srequirenonroot`
- [ ] Constraint applied: `kubectl get k8srequirenonroot`
- [ ] Root containers blocked: attempt to deploy a root container fails
- [ ] Non-root containers allowed: deploy with `runAsNonRoot: true` succeeds
- [ ] Istio sidecar exempted: pods with Istio injection start successfully
- [ ] Vault is initialized and unsealed: `vault status`
- [ ] Vault Kubernetes auth configured: `vault auth list` shows `kubernetes/`
- [ ] Services can read secrets from Vault
- [ ] Network policies applied: `kubectl get networkpolicy -n production`
- [ ] Allowed traffic works: API Gateway → User Service succeeds
- [ ] Blocked traffic denied: direct cross-service database access fails
- [ ] Audit logging active: `vault audit list` shows two file devices

---

## 6. Troubleshooting

### Pods rejected by Gatekeeper unexpectedly

```bash
# Check which constraints are enforced
kubectl get constraints

# Check the violation details
kubectl describe k8srequirenonroot require-non-root-containers

# If a legitimate image is being blocked, add it to exemptImages
```

### Vault sealed after restart

```bash
# Check seal status
kubectl exec -n vault vault-0 -- vault status

# If KMS auto-unseal is configured correctly, Vault should unseal automatically
# Check Vault logs for KMS errors:
kubectl logs -n vault vault-0
```

### Network policy blocking legitimate traffic

```bash
# Check if the network policy is too restrictive
kubectl describe networkpolicy user-service -n production

# Test connectivity from the blocked pod
kubectl exec -n production deploy/api-gateway -- curl -v http://user-service:3001/health

# Verify label selectors match
kubectl get pods -n production --show-labels
```

### Vault agent injector not injecting secrets

```bash
# Check agent injector logs
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector

# Verify pod annotations are correct
kubectl get pod <pod-name> -n production -o yaml | grep vault

# Required annotations:
# vault.hashicorp.com/agent-inject: "true"
# vault.hashicorp.com/role: "user-service"
```

---

## 7. Key Decisions & Trade-offs

| Decision | Chosen | Alternative | Rationale |
|----------|--------|-------------|-----------|
| **Gatekeeper vs. Kyverno** | Gatekeeper (OPA) | Kyverno | Industry standard, Rego is powerful for complex policies. Trade-off: steeper learning curve than Kyverno's YAML-based policies. |
| **Vault vs. AWS Secrets Manager** | Vault | AWS Secrets Manager + ESO | Cross-cloud, dynamic secrets, advanced policies. Trade-off: operational overhead of running Vault. |
| **Consul storage** | Consul | Integrated Raft | HA built-in, service discovery integration. Trade-off: another system to manage. |
| **Network Policies** | Kubernetes native | Calico/Cilium policies | Portable across CNI providers. Trade-off: less advanced features (L7 filtering). |
| **KMS auto-unseal** | AWS KMS | Shamir key shares | No human intervention on restart. Trade-off: depends on AWS KMS availability. |

---

## 8. Production Considerations

- **Policy testing** — Use `gator test` CLI to test Gatekeeper policies in CI before deploying
- **Dry-run mode** — Start Gatekeeper constraints in `dryrun` enforcement mode, then switch to `deny` after validation
- **Secret rotation** — Configure Vault dynamic database credentials with short TTLs (1 hour) for automatic rotation
- **Break-glass procedure** — Document how to override policies in emergencies (e.g., Gatekeeper `dryrun` switch)
- **Compliance scanning** — Run CIS Kubernetes benchmarks regularly with `kube-bench`
- **Falco** — Add Falco for runtime anomaly detection (file access, network connections, process execution)
- **Pod Security Standards** — Enable Kubernetes Pod Security Admission as a secondary layer

---

## 9. Next Phase

**[Phase 10: Chaos Engineering & Resilience →](../phase-10-chaos/README.md)**

With security controls in place, Phase 10 validates that the platform can withstand failures — pod kills, AZ outages, and network disruptions — through structured chaos experiments and game days.

---

[← Phase 8: Observability](../phase-08-observability/README.md) | [Back to Project Overview](../README.md) | [Phase 10: Chaos Engineering →](../phase-10-chaos/README.md)
