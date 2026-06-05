# Lab 16: Kubernetes Security — RBAC, Network Policies & Vault — Architecture Deep Dive

> **Architect:** Vanessa Awo  
> **Framework:** AWS Well-Architected Framework (6 Pillars) + CIS Kubernetes Benchmark  
> **Scope:** 6-layer defense-in-depth — RBAC, NetworkPolicies, Trivy Operator, Falco runtime detection, OPA Gatekeeper, HashiCorp Vault

---

## What This Framework Solves

A Kubernetes cluster with default settings is a flat network where every pod can reach every other pod, every user has cluster-admin access, secrets are base64-encoded values in etcd (not encrypted), and container images are deployed without scanning. Compromising any single pod in this environment means compromising the entire cluster. This lab implements the six security layers that convert a flat default cluster into a defense-in-depth environment where each layer must be independently bypassed.

---

## Architecture: Six Security Layers

```
Layer 1: RBAC (who can call the Kubernetes API)
  cluster-admin → platform team only
  namespace-admin → team lead (their namespace only)
  developer → read-only in their namespace
  monitoring → get/list pods and metrics (all namespaces)

Layer 2: NetworkPolicies (which pods can talk to which pods)
  default-deny-all in every namespace
  explicit allows: frontend→backend, backend→database, monitoring→all

Layer 3: Trivy Operator (CVE scanning at deploy time)
  scans every new deployment's images automatically
  VulnerabilityReport CRDs: queryable with kubectl

Layer 4: Falco (suspicious runtime behavior detection)
  alert on: shell in container, unexpected outbound connections
  alert on: /etc/shadow read, privilege escalation, crypto mining

Layer 5: OPA Gatekeeper (admission control — block before create)
  deny: privileged containers
  deny: :latest image tags
  deny: missing resource limits
  deny: containers running as root UID

Layer 6: HashiCorp Vault (secrets management)
  pod authenticates via Kubernetes ServiceAccount JWT
  Vault issues short-lived, auto-rotating credentials
  no static secrets in Kubernetes Secret objects
```

---

## Step-by-Step: Security Layer Implementation

### Step 1 — RBAC (Least-Privilege Access Control)

```yaml
# rbac/namespace-roles.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: sre-demo
rules:
  # Read-only access to workloads
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "daemonsets"]
    verbs: ["get", "list", "watch"]
  
  # Can read pods and their logs
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  
  # Cannot: create, update, delete, exec, port-forward
  # Cannot: access secrets, configmaps with credentials
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: monitoring-scraper
  namespace: sre-demo
rules:
  # Prometheus needs to list pods to discover scrape targets
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints"]
    verbs: ["get", "list", "watch"]
  # Nothing else — no deployment access, no secrets
```

**Why namespace-scoped Roles rather than ClusterRoles bound to specific namespaces?**  
A ClusterRole defines permissions globally; a RoleBinding scopes it to a namespace. This pattern is common but has a subtle risk: if the ClusterRole is later modified (permissions expanded), all bindings across all namespaces are affected simultaneously. A namespace-scoped Role with a RoleBinding is fully contained — its permissions only affect the one namespace, and changes to one team's role don't affect other teams.

**Why does the developer role explicitly NOT include `pods/exec`?**  
`kubectl exec` opens a shell inside a running container. An exec session bypasses all application-level logging and can be used to exfiltrate data, modify running application state, or escalate to a node-level compromise. Developers should debug via logs (`pods/log`) and describe output, not shell access. If shell access is required for a specific debugging task, it should be granted temporarily via a RoleBinding with a short TTL.

### Step 2 — NetworkPolicies (Zero-Trust Pod Networking)

```yaml
# network-policies/default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: sre-demo
spec:
  podSelector: {}    # matches ALL pods in the namespace
  policyTypes:
    - Ingress
    - Egress
---
# network-policies/app-policies.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-checkout-to-payment
  namespace: sre-demo
spec:
  podSelector:
    matchLabels:
      app: paymentservice
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: checkoutservice
      ports:
        - port: 50051  # gRPC only — not port 80, not arbitrary ports
---
# network-policies/monitoring-access.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scraping
  namespace: sre-demo
spec:
  podSelector: {}    # all pods
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - port: 8080  # metrics port only
```

**Critical deployment order: apply allow rules BEFORE the deny-all.**  
Applying `default-deny-all` first immediately drops all pod-to-pod traffic — the Online Boutique application stops functioning entirely. The correct sequence: (1) apply all allow rules, (2) verify services still communicate, (3) apply the deny-all. From that point, only traffic matching allow rules is permitted. Any new service must have an explicit allow rule before it can communicate.

**Why specify `port: 50051` rather than allowing all ports?**  
A NetworkPolicy that allows all traffic between checkoutservice and paymentservice means checkoutservice could open a connection to paymentservice on any port — including ports intended only for administrative interfaces. Specifying the exact gRPC port (50051) ensures checkoutservice can only use the intended communication channel, not administrative or diagnostic ports.

**Why does the monitoring NetworkPolicy use `namespaceSelector` rather than `podSelector`?**  
Prometheus runs in the `monitoring` namespace, not in `sre-demo`. A `podSelector` can only reference pods in the same namespace as the NetworkPolicy. To allow cross-namespace traffic, `namespaceSelector` is required. The `monitoring` namespace must have the label `name: monitoring` for this rule to match — a subtle dependency that is easy to miss when setting up the monitoring namespace.

### Step 3 — Trivy Operator (Continuous Image Scanning)

```yaml
# scanning/trivy-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: trivy-system
---
# Deployed via Helm:
# helm install trivy-operator aquasecurity/trivy-operator \
#   --namespace trivy-system \
#   --set trivyOperator.scanJobTimeout=5m \
#   --set vulnerabilityReportsPlugin.trivy.severity=CRITICAL,HIGH \
#   --set operator.vulnerabilityScannerEnabled=true \
#   --set operator.configAuditScannerEnabled=true

# After deployment, query results:
# kubectl get vulnerabilityreports -n sre-demo
# kubectl describe vulnerabilityreport frontend-xxx -n sre-demo
```

**Why Trivy Operator (continuous) rather than Trivy in CI only?**  
CI scanning catches CVEs in images when they are built. New CVEs are published daily — a clean image from Monday may have a critical CVE published Thursday. The Trivy Operator rescans running images periodically, detecting newly published CVEs in images that were clean when originally scanned. CI scanning is necessary but not sufficient; operator-based continuous scanning closes the temporal gap.

### Step 4 — Falco Runtime Security

```yaml
# scanning/falco-rules.yaml
customRules:
  custom-rules.yaml: |-
    # Detect shell in container (most common post-compromise signal)
    - rule: Terminal shell in container
      desc: Alert if a shell is spawned in a container
      condition: >
        spawned_process and
        container and
        shell_procs and
        proc.tty != 0
      output: >
        Shell spawned in container
        (user=%user.name pod=%k8s.pod.name ns=%k8s.ns.name
         command=%proc.cmdline)
      priority: WARNING
    
    # Detect unexpected outbound connections
    - rule: Unexpected outbound network connection
      desc: Alert on network connections to unexpected destinations
      condition: >
        outbound and
        container and
        not proc.name in (known_network_processes) and
        not fd.sip in (trusted_ips)
      output: >
        Unexpected outbound connection
        (command=%proc.cmdline connection=%fd.name pod=%k8s.pod.name)
      priority: WARNING
    
    # Detect privilege escalation
    - rule: Container running as root
      desc: Alert when process elevates to root
      condition: >
        container and
        proc.vpid = 1 and
        user.uid = 0 and
        not allowed_root_containers
      output: "Container running as root (pod=%k8s.pod.name)"
      priority: ERROR
```

**Why Falco (syscall-level detection) when OPA Gatekeeper prevents privileged containers at admission?**  
OPA Gatekeeper prevents privileged containers from being *created*. If an attacker finds an application-level vulnerability that allows command injection, they can spawn a shell inside a non-privileged container — bypassing admission control entirely because the container was legitimately created. Falco monitors syscalls at runtime and alerts when a shell is spawned (regardless of how the container was started). The two layers catch different threat vectors.

**Why `proc.tty != 0` as the shell detection condition?**  
`proc.tty != 0` means the process has a terminal attached — i.e., it's an interactive shell session. A process like `sh -c "echo hello"` (a non-interactive shell invoked by a script) would have `proc.tty = 0` and would not match. This condition reduces false positives from legitimate use of shell in init scripts and health check commands.

### Step 5 — OPA Gatekeeper Admission Control

```yaml
# scanning/opa-policies/templates.yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8snolatestimage
spec:
  crd:
    spec:
      names:
        kind: K8sNoLatestImage
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8snolatestimage
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          endswith(container.image, ":latest")
          msg := sprintf("Container '%v' uses ':latest' tag — specify an exact tag", [container.name])
        }
---
# scanning/opa-policies/constraints.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNoLatestImage
metadata:
  name: no-latest-image
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "DaemonSet", "StatefulSet"]
```

**Why block `:latest` image tags at admission rather than as a CI lint rule?**  
A CI lint rule is advisory — it fails the CI pipeline but does not prevent a developer from applying the manifest directly with `kubectl apply`. OPA Gatekeeper operates in the Kubernetes admission webhook path — the API server rejects the resource before it is created, regardless of how it was submitted. There is no bypass.

**Why does this admission control run in the Kubernetes API server (not in a separate service)?**  
OPA Gatekeeper registers as a ValidatingAdmissionWebhook. Every resource creation/update request to the API server is sent to the webhook synchronously — the API server waits for the webhook response before accepting or rejecting the resource. If the webhook returns "deny," the resource is rejected with an error message. There is no eventual consistency: policies are enforced at the moment of submission.

### Step 6 — HashiCorp Vault (Dynamic Secrets)

```hcl
# vault/vault-policies.hcl
path "database/creds/app-role" {
  capabilities = ["read"]
  # Returns: username + password valid for 1 hour, auto-revoked after TTL
}

path "secret/data/sre-demo/*" {
  capabilities = ["read"]
}
```

```yaml
# vault/vault-k8s-auth.yaml — Kubernetes authentication method
# Pods authenticate using their ServiceAccount JWT token
# Vault verifies the JWT against the Kubernetes API

# Application code (using vault-agent sidecar injection):
# vault-agent reads the ServiceAccount token from
# /var/run/secrets/kubernetes.io/serviceaccount/token
# authenticates to Vault, retrieves database credentials
# writes credentials to shared memory (/vault/secrets/db-creds)
# rotates credentials automatically before TTL expires
```

**Why Kubernetes ServiceAccount authentication (not static Vault tokens)?**  
Static Vault tokens are secrets that must be stored somewhere — if stored in a Kubernetes Secret, they are base64-encoded strings that any user with `kubectl get secret` access can read. Kubernetes ServiceAccount JWT tokens are issued by the cluster, have a short TTL, and are automatically mounted into pods. Vault validates the JWT against the Kubernetes API — no secret needs to be stored anywhere. The authentication mechanism itself is stateless.

**Why short-lived dynamic credentials (1-hour TTL) rather than long-lived static passwords?**  
A static database password that never changes is a credential that, once compromised, provides permanent access until manually rotated. A dynamic credential valid for 1 hour requires an attacker to continuously re-authenticate to maintain access — and any gap in re-authentication revokes access automatically. Vault's lease system also ensures that when a pod terminates, its credentials are revoked immediately, even before the 1-hour TTL expires.

---

## AWS Well-Architected Framework Analysis

### Operational Excellence
- **OPA Gatekeeper prevents known misconfigurations at admission:** Developers get immediate, actionable error messages when they submit non-compliant resources — no waiting for a security review
- **ChaosResult CRDs:** Compliance state (`kubectl get vulnerabilityreports`) is queryable in the same way as application state — no separate security dashboard required

### Security
- **Six independent layers:** Each layer must be independently bypassed for a full compromise — no single vulnerability breaks the entire security posture
- **Default-deny NetworkPolicies:** Lateral movement between pods requires an explicit allow rule — a compromised `productcatalogservice` cannot reach `paymentservice`'s credentials
- **Vault dynamic credentials:** Database passwords have a 1-hour TTL — compromised credentials expire automatically without requiring manual rotation

### Reliability
- **NetworkPolicy ordering (allow before deny):** Applying deny-all first causes an outage; the correct sequencing is documented and enforced as a deployment procedure
- **Falco tuning:** Noisy rules that fire on legitimate shell usage in init containers must be tuned before alerting is enabled — initial false-positive cleanup is planned, not a surprise

### Performance Efficiency
- **Vault agent sidecar:** Credential rotation happens in the sidecar process — no application code changes needed for secrets management
- **OPA admission webhook:** Policy evaluation happens synchronously in the API server path — no separate orchestration layer

### Cost Optimization
- **Trivy Operator over commercial scanner:** Trivy is open-source with equivalent CVE coverage to commercial alternatives at zero licensing cost
- **OPA Gatekeeper prevents costly misconfigurations:** A deployed privileged container in production that needs emergency remediation costs more than the prevention check

### Sustainability
- **Least-privilege RBAC:** Developers cannot accidentally over-provision or delete resources they shouldn't touch — reduces toil from unintended resource accumulation

---

## Key Architectural Insight

The principle that makes this six-layer framework coherent is **defense in depth applied at different points in the attack timeline**: OPA Gatekeeper prevents known misconfigurations from being created; Trivy catches CVEs before images run; NetworkPolicies contain blast radius if a pod is compromised; Falco detects compromise in real time; RBAC limits what a compromised human credential can do; Vault limits what a compromised application credential can do. Each layer addresses a different phase of an attack — prevention, detection, or containment. A cluster with only one layer (e.g., only RBAC) is one vulnerability away from full compromise. A cluster with all six layers requires an attacker to find and exploit six independent security controls simultaneously.

---

*Built by Vanessa Awo | [LinkedIn](https://linkedin.com/in/vanessajen) | [Portfolio](https://jenellavan.com)*
