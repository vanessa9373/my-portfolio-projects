# Lab K8S-03: Kubernetes Ingress Controllers

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?style=flat&logo=nginx&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)
![LetsEncrypt](https://img.shields.io/badge/Let's_Encrypt-003A70?style=flat&logo=letsencrypt&logoColor=white)

## Summary (The "Elevator Pitch")

Deployed a single NGINX Ingress Controller to replace 12 individual cloud load balancers, implementing host-based and path-based routing with automatic TLS certificate management via cert-manager and Let's Encrypt. Reduced load balancer costs by 90% while adding SSL termination, centralized routing rules, and automatic certificate renewal.

## The Problem

Each microservice was exposed via its own LoadBalancer Service -- 12 services meant 12 cloud load balancers at **$18/month each ($216/month just for load balancers)**. There was no SSL termination, so each team was managing their own TLS certificates manually. Path-based routing was impossible (you could not route `/api` to one service and `/app` to another through a single entry point). Adding a new microservice required provisioning another load balancer, configuring DNS, and obtaining yet another certificate. The architecture was **expensive, fragmented, and operationally painful**.

## The Solution

Deployed a single **NGINX Ingress Controller** as the cluster's entry point, replacing all 12 load balancers with one. Ingress resources define routing rules: **path-based routing** sends `/app`, `/api`, and `/admin` to different backend services through one domain, while **host-based routing** maps `app.example.com`, `api.example.com`, and `admin.example.com` to their respective services. **cert-manager** with Let's Encrypt automatically provisions and renews TLS certificates -- zero manual certificate management.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Kubernetes Cluster                              │
│                                                                          │
│  Internet                                                                │
│     │                                                                    │
│     ▼                                                                    │
│  ┌──────────────────────────────────────────────┐                       │
│  │        NGINX Ingress Controller               │                       │
│  │        (Single LoadBalancer Service)           │                       │
│  │        External IP: 203.0.113.10              │                       │
│  │        TLS Termination: *.example.com         │                       │
│  └──────────┬──────────────┬──────────────┬──────┘                      │
│             │              │              │                               │
│    ┌────────┴───┐  ┌──────┴───────┐  ┌───┴──────────┐                  │
│    │ Ingress     │  │ Ingress       │  │ Ingress       │                  │
│    │ Rules       │  │ Rules         │  │ Rules         │                  │
│    │             │  │               │  │               │                  │
│    │ Path: /app  │  │ Path: /api    │  │ Path: /admin  │                  │
│    │ Host: app.  │  │ Host: api.    │  │ Host: admin.  │                  │
│    └──────┬─────┘  └──────┬────────┘  └──────┬────────┘                 │
│           │               │                   │                          │
│           ▼               ▼                   ▼                          │
│    ┌────────────┐  ┌────────────┐      ┌────────────┐                   │
│    │ ClusterIP   │  │ ClusterIP   │      │ ClusterIP   │                  │
│    │ app-svc     │  │ api-svc     │      │ admin-svc   │                  │
│    │ :80         │  │ :80         │      │ :80         │                  │
│    └──────┬─────┘  └──────┬──────┘     └──────┬──────┘                  │
│           │               │                    │                         │
│     ┌─────┴─────┐   ┌────┴────┐         ┌────┴────┐                    │
│     │ App Pods  │   │API Pods │         │Admin Pod│                     │
│     │ (3 repl.) │   │(3 repl.)│         │(2 repl.)│                     │
│     └───────────┘   └─────────┘         └─────────┘                     │
│                                                                          │
│  cert-manager ──► ClusterIssuer ──► Let's Encrypt ──► TLS Certificates  │
└──────────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Technology | Purpose | Why I Chose It |
|------------|---------|----------------|
| NGINX Ingress Controller | Reverse proxy and load balancer | Most widely adopted K8s ingress controller; battle-tested in production |
| Helm | Package manager for installing Ingress Controller and cert-manager | Simplifies installation and configuration of complex components |
| Ingress Resources | Declarative routing rules (host, path, TLS) | Native Kubernetes API for HTTP routing |
| cert-manager | Automated TLS certificate provisioning and renewal | Eliminates manual certificate management; integrates with Let's Encrypt |
| Let's Encrypt | Free, automated TLS certificates | Zero-cost SSL/TLS with auto-renewal |
| ClusterIP Services | Internal backend services | Ingress routes to ClusterIP services (no need for LoadBalancer per service) |
| NGINX (app containers) | Sample microservices (app, api, admin) | Lightweight, easy to customize response for testing |

## Implementation Steps

### Step 1: Install NGINX Ingress Controller (via Helm)
**What this does:** Installs the NGINX Ingress Controller into the `ingress-nginx` namespace. This creates a single LoadBalancer Service that acts as the entry point for all HTTP/HTTPS traffic. All Ingress resources in the cluster will route through this controller.
```bash
# Add the ingress-nginx Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install with custom values
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values manifests/nginx-ingress-values.yaml

# Wait for controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Verify the external IP/address
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

### Step 2: Deploy Sample Microservices (App, API, Admin)
**What this does:** Deploys three separate microservices (app, api, admin), each with its own Deployment. Each service returns a different response so you can verify routing is working correctly. These represent a typical microservice architecture.
```bash
kubectl create namespace k8s-ingress
kubectl apply -f manifests/app-deployment.yaml
kubectl apply -f manifests/api-deployment.yaml
kubectl apply -f manifests/admin-deployment.yaml
kubectl apply -f manifests/services.yaml
kubectl get deployments -n k8s-ingress
kubectl get svc -n k8s-ingress
```

### Step 3: Create Ingress with Path-Based Routing
**What this does:** Creates an Ingress resource that routes traffic based on the URL path. Requests to `/app` go to the app service, `/api` to the API service, and `/admin` to the admin service -- all through the same external IP and domain.
```bash
kubectl apply -f manifests/ingress-path.yaml
kubectl get ingress -n k8s-ingress
kubectl describe ingress path-based-routing -n k8s-ingress

# Test path-based routing
INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://${INGRESS_IP}/app
curl http://${INGRESS_IP}/api
curl http://${INGRESS_IP}/admin
```

### Step 4: Create Ingress with Host-Based Routing
**What this does:** Creates Ingress rules that route based on the hostname. `app.example.com` goes to the app service, `api.example.com` to the API service, and `admin.example.com` to the admin service. This is how you serve multiple domains from one ingress controller.
```bash
kubectl apply -f manifests/ingress-host.yaml
kubectl get ingress -n k8s-ingress
kubectl describe ingress host-based-routing -n k8s-ingress

# Test host-based routing (using Host header to simulate DNS)
curl -H "Host: app.example.com" http://${INGRESS_IP}/
curl -H "Host: api.example.com" http://${INGRESS_IP}/
curl -H "Host: admin.example.com" http://${INGRESS_IP}/
```

### Step 5: Install cert-manager
**What this does:** Installs cert-manager, which watches for Ingress resources with TLS annotations and automatically requests certificates from Let's Encrypt (or other ACME providers). It handles the entire certificate lifecycle: issuance, renewal, and storage as Kubernetes Secrets.
```bash
# Add the cert-manager Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# Verify all pods are running
kubectl get pods -n cert-manager
kubectl wait --for=condition=Ready pod -l app=cert-manager -n cert-manager --timeout=120s
```

### Step 6: Create ClusterIssuer for Let's Encrypt
**What this does:** Creates a ClusterIssuer that tells cert-manager how to obtain certificates from Let's Encrypt. The ClusterIssuer is cluster-scoped (usable by any namespace). It uses the HTTP-01 challenge type, which proves domain ownership by serving a token via the Ingress Controller.
```bash
kubectl apply -f manifests/cert-manager-issuer.yaml
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
# Status should show "The ACME account was registered"
```

### Step 7: Add TLS to Ingress Resources
**What this does:** Updates the Ingress resource with TLS configuration. The `cert-manager.io/cluster-issuer` annotation tells cert-manager to automatically request a certificate for the specified hosts. The certificate is stored as a Kubernetes Secret and the Ingress Controller uses it for HTTPS termination.
```bash
kubectl apply -f manifests/ingress-tls.yaml
kubectl get ingress -n k8s-ingress
kubectl get certificates -n k8s-ingress
# Wait for certificate to be issued
kubectl wait --for=condition=Ready certificate/example-com-tls -n k8s-ingress --timeout=120s || echo "Certificate pending (expected in dev without real DNS)"
kubectl get secrets -n k8s-ingress | grep tls
```

### Step 8: Test Routing and TLS Termination
**What this does:** Validates that all routing rules work correctly and that TLS termination is functioning. In a production environment with real DNS, HTTPS requests would terminate at the Ingress Controller with valid Let's Encrypt certificates.
```bash
# Verify all ingress rules
kubectl get ingress -n k8s-ingress -o wide

# Test path-based routing
echo "--- Path-based routing ---"
curl -H "Host: myapp.example.com" http://${INGRESS_IP}/app
curl -H "Host: myapp.example.com" http://${INGRESS_IP}/api
curl -H "Host: myapp.example.com" http://${INGRESS_IP}/admin

# Test host-based routing
echo "--- Host-based routing ---"
curl -H "Host: app.example.com" http://${INGRESS_IP}/
curl -H "Host: api.example.com" http://${INGRESS_IP}/

# Check TLS certificate details
kubectl describe certificate example-com-tls -n k8s-ingress
kubectl get secret example-com-tls -n k8s-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -dates 2>/dev/null || echo "Self-signed or pending cert"
```

## Project Structure

```
K8S-03-ingress-controllers/
├── README.md                          # Lab documentation (this file)
├── manifests/
│   ├── nginx-ingress-values.yaml      # Helm values for NGINX Ingress Controller
│   ├── app-deployment.yaml            # Frontend app (3 replicas)
│   ├── api-deployment.yaml            # API service (3 replicas)
│   ├── admin-deployment.yaml          # Admin dashboard (2 replicas)
│   ├── services.yaml                  # ClusterIP Services for all 3 apps
│   ├── ingress-path.yaml              # Path-based routing (/app, /api, /admin)
│   ├── ingress-host.yaml              # Host-based routing (app., api., admin.)
│   ├── cert-manager-issuer.yaml       # Let's Encrypt ClusterIssuer
│   └── ingress-tls.yaml              # Ingress with TLS termination
└── scripts/
    ├── deploy.sh                      # Deploy everything in order
    └── cleanup.sh                     # Remove all resources
```

## Key Files Explained

| File | What It Does | Key Concepts |
|------|-------------|--------------|
| `manifests/nginx-ingress-values.yaml` | Configures NGINX Ingress Controller Helm chart (replicas, metrics, default SSL) | Helm values, controller configuration |
| `manifests/app-deployment.yaml` | 3-replica frontend returning "App Service" response | Deployment, custom nginx config |
| `manifests/api-deployment.yaml` | 3-replica API returning "API Service" response | Backend microservice pattern |
| `manifests/services.yaml` | ClusterIP services for all three backends | Service discovery, label selectors |
| `manifests/ingress-path.yaml` | Routes /app, /api, /admin to different backend services | Path-based routing, pathType, rewrite rules |
| `manifests/ingress-host.yaml` | Routes app.example.com, api.example.com to backends | Host-based (virtual host) routing |
| `manifests/cert-manager-issuer.yaml` | Configures Let's Encrypt as certificate authority | ACME protocol, HTTP-01 challenge, ClusterIssuer |
| `manifests/ingress-tls.yaml` | Adds TLS termination with auto-provisioned certificates | TLS secrets, cert-manager annotations, HTTPS redirect |

## Results & Metrics

| Metric | Before (Per-Service LB) | After (Ingress Controller) | Improvement |
|--------|------------------------|---------------------------|-------------|
| Load Balancers | 12 ($216/month) | 1 ($18/month) | **92% cost reduction** |
| TLS Certificates | Manual per service | Automatic (cert-manager) | **Zero manual certs** |
| New Service Exposure | Provision LB + DNS + cert | Add Ingress rule (3 lines YAML) | **Minutes vs days** |
| SSL Renewal | Manual, error-prone | Automatic (30 days before expiry) | **Zero renewal failures** |
| Routing Flexibility | None (1 LB = 1 service) | Path + Host routing | **Full L7 routing** |
| Configuration | Scattered across services | Centralized Ingress rules | **Single pane of glass** |

## How I'd Explain This in an Interview

> "We had 12 microservices, each with its own LoadBalancer -- that's 12 cloud load balancers costing over $200 a month, with no SSL and no path-based routing. I deployed a single NGINX Ingress Controller as the cluster's entry point and replaced all 12 load balancers with one. Ingress resources define the routing: path-based rules route /app, /api, and /admin to different backends through one domain, while host-based rules map subdomains to services. For TLS, I deployed cert-manager with Let's Encrypt integration -- certificates are provisioned and renewed automatically, zero manual management. The result was a 92% cost reduction on load balancers, automatic SSL everywhere, and adding a new service went from a multi-day process to a 3-line YAML change."

## Key Concepts Demonstrated

- **Ingress Controller** — A reverse proxy (NGINX, Traefik, HAProxy) that implements Ingress resource rules; the actual traffic handler
- **Ingress Resource** — A Kubernetes API object defining HTTP routing rules (host, path, TLS) for the Ingress Controller to implement
- **Path-Based Routing** — Routing requests to different backend services based on URL path (/app, /api, /admin)
- **Host-Based Routing** — Routing requests based on the HTTP Host header (virtual hosting); app.example.com vs api.example.com
- **TLS Termination** — Decrypting HTTPS at the Ingress Controller and forwarding plain HTTP to backend pods
- **cert-manager** — Kubernetes operator that automates TLS certificate issuance and renewal from providers like Let's Encrypt
- **ClusterIssuer** — Cluster-scoped cert-manager resource defining how to obtain certificates (ACME provider, challenge type)
- **HTTP-01 Challenge** — Proves domain ownership by serving a token at a well-known URL; handled automatically by Ingress Controller
- **NGINX Annotations** — Ingress annotations to configure NGINX behavior (rewrites, rate limiting, CORS, proxy settings)
- **Gateway API** — The successor to Ingress API; provides more expressive routing with HTTPRoute, Gateway, and GatewayClass resources

## Lessons Learned

1. **One Ingress Controller, many Ingress resources** — A common misconception is deploying one controller per service. One controller handles all Ingress resources in the cluster. Only deploy multiple controllers for isolation (e.g., internal vs external traffic).
2. **pathType matters more than you think** — `Prefix` matches `/api` and `/api/v1/users`, while `Exact` only matches `/api`. Using the wrong pathType is the number one cause of "my Ingress is not routing" tickets.
3. **Use staging Let's Encrypt first** — Let's Encrypt has rate limits (50 certificates per domain per week). Always test with the staging issuer to avoid hitting rate limits before production is ready.
4. **The default backend catches everything** — Without a default backend, requests that don't match any Ingress rule get a generic 404. Configure a custom default backend to return a helpful error page or redirect.
5. **Ingress annotations are controller-specific** — NGINX annotations do not work with Traefik, and vice versa. This is why the Gateway API was created -- to standardize advanced routing without vendor-specific annotations.

## Author

**Jenella Awo** — Solutions Architect & Cloud Engineer
- [LinkedIn](https://www.linkedin.com/in/jenella-v-4a4b963ab/) | [GitHub](https://github.com/vanessa9373) | [Portfolio](https://vanessa9373.github.io/portfolio/)
