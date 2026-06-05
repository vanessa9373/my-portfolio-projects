# DevOps & Cloud Engineering Portfolio — Project Summary

This document explains **what each project does**, **why every tool and command was chosen**, and **how the projects connect** to form a complete DevOps engineering skillset. Each section answers three questions: *What are we building? Why this approach? Where does it lead?*

---

## How the Projects Connect

The 18 standalone labs, the comprehensive mastery project, and the Kubernetes learning path are not random — they follow a deliberate progression that mirrors how real infrastructure evolves at a company:

```
Foundation                  Operations                  Maturity
─────────────────────────  ─────────────────────────  ─────────────────────────
01 Cloud Migration          08 Observability            13 Chaos Engineering
02 Multi-Cloud              09 SRE/SLO Platform         14 Chaos (Litmus)
03 Terraform Modules        10 Logging & Tracing        15 Security & Compliance
04 IaC (Terraform+Ansible)  11 Incident Response        16 Kubernetes Security
05 CI/CD + Kubernetes       12 Auto-Remediation         17 Serverless Pipeline
06 CI/CD + GitOps                                       18 FinOps/Cost Optimization
07 Canary Deployments                                   19 Full Lifecycle Mastery
                                                        K8s Learning Path (18 labs)
```

You build the platform first (Labs 1-7), then make it observable and reliable (Labs 8-12), then harden, optimize, and scale it (Labs 13-19).

---

## Lab 01: Enterprise Cloud Migration — On-Prem to AWS

### What We're Building

A migration from on-premises infrastructure to AWS. The legacy monolithic application is re-architected into containerized microservices running on ECS Fargate with Aurora PostgreSQL as the managed database and an ALB (Application Load Balancer) distributing traffic.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Terraform** | Defines all AWS resources as code so the entire environment can be recreated, versioned, and reviewed in pull requests. Manual console clicking doesn't scale and can't be audited. |
| **ECS Fargate** | Runs containers without managing EC2 instances. We chose Fargate over EKS here because the workload is a simple lift-and-shift — Kubernetes adds complexity that isn't needed yet. |
| **Aurora PostgreSQL** | AWS-managed database with automatic failover, backups, and replication. Eliminates the operational burden of self-managed database servers. |
| **ALB** | Routes HTTP/HTTPS traffic to healthy containers. Health checks automatically stop sending traffic to failed instances. |
| **CloudWatch** | Centralized logging and metrics. Without observability, we're flying blind after migration. |
| **Docker** | Packages the application with its dependencies so it runs identically on a developer's laptop, in CI, and in production. Eliminates "works on my machine" problems. |

### Why Each Command Matters

- `terraform init` — Downloads the AWS provider plugin and sets up the backend for state storage. Without this, Terraform doesn't know how to talk to AWS.
- `terraform plan` — Shows exactly what will be created, changed, or destroyed *before* touching anything. This is the safety net that prevents accidental infrastructure damage.
- `terraform apply` — Actually provisions the resources. We always run `plan` first so there are no surprises.
- `docker build` — Creates the container image from the Dockerfile. The multi-stage build keeps the production image small by discarding build tools.
- `docker push` — Uploads the image to ECR (Elastic Container Registry) so ECS can pull it during deployment.

### Where This Leads

This migration establishes the cloud foundation. Once the application is running on AWS, Lab 02 extends it to multi-cloud, Lab 04 adds Ansible for configuration management, and Lab 05 automates deployments with CI/CD.

**Key Results:** 35% cost reduction, 99.95% uptime, 30-minute provisioning (was 2 weeks)

---

## Lab 02: Multi-Cloud Hybrid Architecture — AWS & Azure

### What We're Building

An active-active architecture spanning both AWS and Azure. Two independent deployments of the same application run in both clouds, connected by an encrypted VPN tunnel. Route 53 distributes traffic to both and automatically fails over if one cloud goes down.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **AWS VPC + Azure VNet** | Each cloud needs its own isolated network. The VPC and VNet are the foundation — everything else (compute, databases, load balancers) lives inside them. |
| **VPN Gateway / Transit Gateway** | Creates an encrypted tunnel between AWS and Azure so services can communicate privately. Without this, cross-cloud traffic would go over the public internet — slower and less secure. |
| **Route 53** | DNS-level failover. If AWS health checks fail, Route 53 automatically redirects all traffic to Azure within 30 seconds. This is the mechanism that delivers 99.99% availability. |
| **EKS + AKS** | Kubernetes in both clouds. Using the same orchestrator means the same Helm charts and deployment manifests work in both environments. |
| **Aurora + Azure SQL** | Managed databases in each cloud. Data replication between them ensures the secondary region has up-to-date data during failover. |

### Why Each Command Matters

- `aws ec2 create-vpn-gateway` — Establishes the AWS side of the VPN tunnel. This is the bridge between clouds.
- `az network vnet-gateway create` — Establishes the Azure side. Both sides must be configured with matching pre-shared keys.
- `terraform apply -var-file=aws.tfvars` / `terraform apply -var-file=azure.tfvars` — Separate variable files keep each cloud's configuration isolated while sharing the same module structure.
- `dig api.example.com` — Verifies DNS failover is routing to the correct cloud. This is how you confirm failover actually works.

### Where This Leads

Multi-cloud teaches you that reliability comes from redundancy across failure domains. Lab 03 extracts the Terraform patterns used here into a reusable module library. Lab 19 (Phase 12) applies the same failover concepts with Route 53 + Aurora Global Database.

**Key Results:** 99.99% availability, <15 min RTO, SOC 2 compliance, zero single points of failure

---

## Lab 03: Production-Grade Multi-Cloud Terraform Module Library

### What We're Building

A library of 40 reusable Terraform modules — 16 for AWS, 12 for Azure, 12 for GCP — each implementing production best practices by default. Instead of writing VPC/EKS/RDS code from scratch for every project, teams use these modules and only configure what's different.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Terraform Modules** | Modules encapsulate infrastructure patterns. A `vpc` module handles subnets, route tables, NAT gateways, and security groups — the team calling the module just specifies a CIDR range. This prevents misconfiguration and enforces standards. |
| **Terratest (Go)** | Automated integration tests that actually provision infrastructure, verify it works, then destroy it. Without tests, module updates can silently break downstream projects. |
| **tflint** | Static analysis catches errors (typos in resource types, deprecated arguments) before `terraform plan` even runs. Faster feedback than waiting for the API to reject the request. |
| **3 Cloud Providers** | Real organizations use multiple clouds. Having modules for AWS, Azure, and GCP means teams can choose the best cloud for each workload without writing IaC from scratch. |

### Why Each Command Matters

- `terraform init -backend-config=...` — Configures where the state file is stored. Each environment (dev, staging, prod) needs its own state file to prevent changes in dev from affecting production.
- `go test -v ./tests/` — Runs the Terratest suite. Each test creates real infrastructure, validates it, and tears it down. This is expensive but catches real bugs.
- `tflint --module` — Scans all module references for issues. Catches problems like referencing a variable that doesn't exist or using a deprecated resource argument.
- `terraform validate` — Checks syntax and internal consistency. Faster than `plan` because it doesn't contact the cloud provider API.

### Where This Leads

These modules are consumed by every other lab that provisions infrastructure. Lab 04 layers Ansible on top for configuration management. Lab 19 uses similar module patterns for EKS, RDS, and VPC provisioning.

**Key Results:** 96% faster environment setup, 10+ client engagements, security-by-default

---

## Lab 04: Infrastructure as Code — Terraform & Ansible

### What We're Building

A two-layer IaC framework: Terraform provisions cloud resources (VPC, EC2, EKS, RDS), then Ansible configures the servers (install Docker, harden security, deploy monitoring agents). This separates *what* exists from *how it's configured*.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Terraform** | Provisions infrastructure — things that have an API you can create/destroy. VPCs, EC2 instances, load balancers, databases. Terraform tracks state and knows what exists. |
| **Ansible** | Configures servers — things that happen *inside* a machine after it's created. Installing packages, copying config files, starting services, hardening security. Ansible is agentless (SSH-based), so there's nothing to install on target machines. |
| **`generate-inventory.sh`** | Terraform creates instances, but Ansible needs to know their IP addresses. This script queries Terraform outputs and generates Ansible's inventory file automatically. Without it, someone would manually copy-paste IPs. |
| **`full-deploy.sh`** | Orchestrates the full pipeline: `terraform apply` → `generate-inventory.sh` → `ansible-playbook`. One command provisions and configures everything. |

### Why Each Command Matters

- `terraform apply -var-file=environments/production.tfvars` — Provisions production infrastructure. The `-var-file` flag separates environment-specific values (instance sizes, counts) from the module code.
- `ansible-playbook -i inventory/production playbooks/security-hardening.yml` — Runs the security hardening playbook against all production servers. Disables root login, configures firewalls, installs fail2ban.
- `ansible-playbook playbooks/setup-monitoring.yml` — Installs Prometheus node exporter and Fluent Bit on every server so metrics and logs flow to the central observability stack.
- `ansible-playbook playbooks/deploy-app.yml --extra-vars "version=1.2.3"` — Deploys a specific application version with zero-downtime rolling updates.

### Where This Leads

This lab establishes the pattern of "provision then configure." Lab 05 replaces manual deployments with CI/CD pipelines. The Ansible patterns for security hardening reappear in Lab 15 (compliance) and Lab 16 (Kubernetes security).

**Key Results:** 96% faster provisioning, zero-downtime deployments, CIS benchmark compliance

---

## Lab 05: CI/CD Pipeline & Kubernetes Deployment Platform

### What We're Building

A fully automated GitOps CI/CD platform. Every code push triggers: lint → test → build Docker image → scan for vulnerabilities → push to ECR → ArgoCD deploys to EKS. Developers push code; everything else is automated.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **GitHub Actions** | CI pipeline that runs on every push and pull request. Native GitHub integration means no separate CI server to manage. Matrix builds test across Node versions and operating systems in parallel. |
| **ArgoCD** | GitOps continuous delivery. ArgoCD watches a Git repository and ensures the Kubernetes cluster matches what's in Git. If someone manually changes the cluster, ArgoCD reverts it. This is the "Git is the source of truth" principle. |
| **EKS** | Managed Kubernetes. AWS handles the control plane (API server, etcd, scheduler) — we only manage the worker nodes. This is the right choice when you need Kubernetes features (auto-scaling, service mesh, rolling updates) but don't want to operate the control plane. |
| **ECR** | Private Docker image registry in AWS. Images stay in the same AWS account as EKS, so pulls are fast and don't cross network boundaries. |
| **Helm** | Package manager for Kubernetes. Instead of managing dozens of YAML files, Helm charts template them with values that change per environment (replica count, image tag, resource limits). |
| **Trivy** | Scans Docker images for known vulnerabilities (CVEs). If a CRITICAL vulnerability is found, the pipeline fails and the image is never deployed. This catches security issues before they reach production. |

### Why Each Command Matters

- `docker build -t $ECR_REGISTRY/$SERVICE:$SHA` — Builds the image and tags it with the Git commit SHA. SHA tags provide exact traceability — you can always know which code is running in production.
- `trivy image --severity CRITICAL,HIGH --exit-code 1` — Scans the image and fails the build if CRITICAL or HIGH CVEs are found. The `--exit-code 1` is critical — without it, Trivy reports but doesn't block.
- `docker push` — Uploads the scanned, clean image to ECR. Only images that pass Trivy scanning reach the registry.
- `argocd app sync` — Tells ArgoCD to reconcile the cluster with the latest Git state. In practice, the CD pipeline updates the image tag in Git, and ArgoCD detects the change automatically.
- `helm upgrade --install` — Deploys (or updates) the service. `--install` makes the command idempotent — it works whether the service exists or not.

### Where This Leads

This is the foundational CI/CD pattern. Lab 06 deepens the GitOps approach. Lab 07 adds canary deployments with Argo Rollouts. Lab 19 (Phase 5) scales these patterns to a 6-service monorepo.

**Key Results:** 10x deployment frequency (1/month → 10/day), 30-second rollbacks, zero-downtime

---

## Lab 06: CI/CD Pipeline with GitOps

### What We're Building

An end-to-end pipeline for a Flask application where every code push is automatically linted, tested, built, scanned for CVEs, and deployed to Kubernetes via ArgoCD — with zero manual steps.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Flask** | A simple Python web framework used as the application under deployment. The focus of this lab is the pipeline, not the application — Flask keeps the app simple so we can focus on CI/CD mechanics. |
| **k3d** | Lightweight Kubernetes cluster running inside Docker containers. Perfect for local development and CI testing — spins up in seconds, costs nothing, and behaves like a real cluster. |
| **Trivy** | Integrated into the pipeline to scan every Docker image before deployment. This is "shift-left security" — finding vulnerabilities in CI instead of after production deployment. |
| **ArgoCD** | Watches the `k8s/` directory in Git. When the CI pipeline updates the image tag in `deployment.yaml`, ArgoCD detects the change and rolls it out to the cluster. No `kubectl apply` anywhere in the pipeline. |

### Why Each Command Matters

- `pytest tests/ --cov=app` — Runs tests with coverage reporting. The `--cov` flag measures which lines of code are tested. Low coverage means unverified code paths that could break in production.
- `docker build -t app:${{ github.sha }}` — Tags with commit SHA for traceability. If production breaks, you can `git log` the SHA to see exactly which commit caused it.
- `trivy image --exit-code 1 --severity CRITICAL,HIGH` — Gate the deployment on security. A single critical CVE in a base image can expose the entire cluster.
- `argocd app sync` — The only deployment command. Everything else is a build step.

### Where This Leads

Lab 06 proves that GitOps works for simple applications. Lab 07 adds progressive delivery (canary) for higher-stakes deployments where you can't afford to send all traffic to a new version at once.

**Key Results:** 95% faster build-to-deploy (hours → 5 minutes), automated CVE scanning, zero manual deployments

---

## Lab 07: CI/CD with ArgoCD & Argo Rollouts

### What We're Building

Progressive delivery with canary deployments. Instead of sending 100% of traffic to a new version immediately, Argo Rollouts shifts traffic gradually — 10% → 30% → 100% — and runs automated analysis at each step. If error rates spike, traffic is automatically rolled back to the previous version.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Argo Rollouts** | Replaces the standard Kubernetes `Deployment` with a `Rollout` resource that supports canary and blue-green strategies. The key difference: Rollouts can *pause* and *analyze* before proceeding. Standard deployments just roll forward. |
| **Prometheus** | Provides the metrics that Argo Rollouts analyzes at each canary step. If the canary version's error rate exceeds the threshold, the rollout is aborted automatically — no human intervention needed. |
| **Helm** | Manages the Rollout manifests. Separate values files for staging and production mean the same chart can deploy with different replica counts, resource limits, and canary configurations. |
| **`promote-canary.sh`** | Manually promotes a canary to 100% traffic. Used when you want human approval before full rollout (e.g., after checking dashboards). |
| **`rollback.sh`** | Emergency rollback script. Tells Argo Rollouts to abort the canary and route all traffic back to the stable version immediately. |

### Why Each Command Matters

- `kubectl argo rollouts set image rollout/app container=app:v2` — Triggers a canary rollout of the new image. Argo Rollouts starts at 10% and pauses for analysis.
- `kubectl argo rollouts get rollout app --watch` — Live view of the rollout progress. Shows current weight, analysis results, and whether the canary passed or failed.
- `kubectl argo rollouts promote app` — Manually promotes the canary to 100%. Used after human review of dashboards and metrics.
- `kubectl argo rollouts abort app` — Immediately rolls back. All traffic returns to the stable version in under a minute.

### Where This Leads

Canary deployments are the production standard for high-traffic services. Lab 19 (Phase 11) takes this further with Istio + Flagger for mesh-level canary routing with even more sophisticated metrics gates.

**Key Results:** 90% blast radius reduction, auto-rollback in <1 minute, zero-downtime deployments

---

## Lab 08: Kubernetes Observability Platform

### What We're Building

A complete monitoring stack for a 12-service microservices application (Google's Online Boutique). Prometheus scrapes metrics from every pod, Grafana visualizes them in dashboards, Alertmanager sends alerts when things go wrong, and HPA automatically scales pods based on CPU usage.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Prometheus** | Pull-based metrics collection. Prometheus scrapes `/metrics` endpoints from every pod on a schedule. Pull-based is better than push-based for Kubernetes because pods come and go — Prometheus discovers them via service discovery. |
| **Grafana** | Visualization layer. Raw Prometheus metrics are numbers — Grafana turns them into dashboards showing request rates, error rates, latency percentiles, and resource usage at a glance. |
| **Alertmanager** | Routes alerts from Prometheus to the right people. Groups related alerts (so you don't get 50 emails when one node goes down), deduplicates, and supports silencing during maintenance windows. |
| **HPA (Horizontal Pod Autoscaler)** | Automatically scales pod count based on metrics. When CPU exceeds 70%, HPA adds pods. When it drops below, HPA removes them. This keeps the application responsive during traffic spikes without over-provisioning during quiet periods. |
| **NetworkPolicies** | Restricts which pods can talk to which. By default, every pod can reach every other pod — NetworkPolicies enforce zero-trust networking so only authorized communication paths exist. |

### Why Each Command Matters

- `helm install prometheus prometheus-community/kube-prometheus-stack` — Installs Prometheus, Grafana, Alertmanager, and node-exporter in one command. The `kube-prometheus-stack` chart is the standard production setup.
- `kubectl port-forward svc/prometheus-grafana 3000:80` — Makes Grafana accessible on your local machine. In production, you'd expose it through an ingress with authentication.
- `kubectl apply -f alerts/pod-alerts.yaml` — Creates alert rules. These are PrometheusRule resources that Prometheus picks up automatically.
- `kubectl apply -f hpa.yaml` — Creates the autoscaler. The HPA controller watches the metric and adjusts replicas every 15 seconds.
- `kubectl apply -f network-policies/` — Applies zero-trust networking. After this, pods can only communicate on explicitly allowed paths.

### Where This Leads

Lab 08 establishes observability fundamentals. Lab 09 builds on this with SLO-based alerting (burn rate instead of threshold alerts). Lab 10 adds the logging and tracing pillars. Lab 19 (Phase 8) combines all three pillars into a production-grade observability stack.

**Key Results:** Full visibility into 12 services, automated alerting, auto-scaling, zero-trust networking

---

## Lab 09: SRE Observability & SLO Platform

### What We're Building

An SLO (Service Level Objective) platform that replaces noisy threshold-based alerts with multi-window burn-rate alerting. Instead of alerting on "error rate > 1%", we alert on "we're consuming our monthly error budget 14x faster than sustainable." This reduces alert noise by 60% while catching real problems faster.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Prometheus Recording Rules** | Pre-compute SLI ratios (availability, latency) at multiple time windows (5m, 30m, 1h, 6h). Without recording rules, every dashboard panel and alert rule would re-compute these ratios from raw data, wasting CPU and adding latency. |
| **Multi-Window Burn Rate** | A 5-minute burn rate catches fast incidents (complete outage). A 6-hour burn rate catches slow-burn issues (gradual degradation). Using multiple windows eliminates false positives from brief spikes and false negatives from slow drifts. |
| **Error Budget** | The SLO is 99.95% availability — that's 21.6 minutes of allowed downtime per month. The error budget tracks how much of that 21.6 minutes has been consumed. When the budget is low, the team shifts from shipping features to improving reliability. |
| **Python SLO Calculator** | Automates the math: given an SLO target, current availability, and time period, how much error budget remains? This eliminates manual spreadsheet calculations. |

### Why Each Command Matters

- `kubectl apply -f prometheus/alerting-rules.yaml` — Loads the 12 burn-rate alert rules into Prometheus. These rules fire at different severity levels based on how fast the error budget is being consumed.
- `python scripts/slo-calculator.py --slo 99.95 --window 30d` — Calculates current error budget consumption. Running this daily gives the team a data-driven view of whether they should ship features or fix reliability.
- `kubectl port-forward svc/grafana 3000:80` — Access the SLO dashboard showing burn rate, error budget, and SLI trends over time.

### Where This Leads

SLO-based alerting is the foundation of SRE practice. Lab 11 adds incident response procedures (runbooks, drills) on top of these alerts. Lab 19 (Phase 8) implements the same SLO rules for the e-commerce platform.

**Key Results:** 60% fewer alerts, 45% faster MTTD, error budget tracking for 50+ services

---

## Lab 10: Logging & Tracing Pipeline (EFK + OpenTelemetry + Jaeger)

### What We're Building

The remaining two pillars of observability — centralized logging (EFK stack) and distributed tracing (OpenTelemetry + Jaeger). Combined with the metrics from Labs 08-09, this provides complete observability: metrics tell you *something is wrong*, logs tell you *what went wrong*, and traces tell you *where in the request chain it went wrong*.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Elasticsearch** | Stores and indexes log data. Elasticsearch's full-text search lets you query logs by service, error message, request ID, or any field — far more powerful than `grep` on individual servers. |
| **Fluent Bit** | Lightweight log shipper deployed as a DaemonSet (one per node). Collects logs from every container on the node, parses them, and forwards to Elasticsearch. Fluent Bit over Fluentd because it uses 10x less memory. |
| **Kibana** | Web UI for searching and visualizing logs. Create dashboards showing error counts by service, search for specific request IDs, and set up saved queries for common debugging patterns. |
| **OpenTelemetry Collector** | Vendor-neutral telemetry pipeline. Receives traces from applications, processes them (sampling, attribute enrichment), and exports to Jaeger. Using OpenTelemetry means you can switch tracing backends without changing application code. |
| **Jaeger** | Distributed tracing UI. Shows the full journey of a request across services — which service was called, how long each call took, and where errors occurred. Essential for debugging microservice architectures where a single user request touches 5+ services. |

### Why Each Command Matters

- `kubectl apply -f logging/fluent-bit.yaml` — Deploys the log collector to every node. From this point, every container log is automatically captured — no per-service configuration needed.
- `kubectl apply -f tracing/otel-collector.yaml` — Deploys the OpenTelemetry Collector. Applications send traces here, and the collector forwards them to Jaeger after sampling.
- `kubectl apply -f logging/index-lifecycle.yaml` — Configures automatic log rotation and deletion. Without lifecycle policies, Elasticsearch storage grows unbounded and eventually crashes.
- `bash scripts/verify-pipeline.sh` — End-to-end verification: sends a test log, queries Elasticsearch for it, sends a test trace, queries Jaeger for it. Confirms the entire pipeline is working.

### Where This Leads

With all three observability pillars in place (metrics, logs, traces), Lab 11 builds incident response procedures, and Lab 12 automates those procedures. Lab 19 (Phase 8) combines Prometheus + Loki + OpenTelemetry for the same three-pillar approach.

**Key Results:** 80% faster debugging, centralized logs from 12+ services, log-trace correlation

---

## Lab 11: Incident Response & SLO Monitoring

### What We're Building

The *operational procedures* that sit on top of the observability stack. SLO dashboards track error budgets, burn-rate alerts page on-call engineers, runbooks provide step-by-step recovery instructions, and simulated incidents validate that everything works before a real outage.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Prometheus Recording Rules** | Pre-compute SLIs at different time windows so alert rules and dashboards query pre-computed values instead of raw data. |
| **Burn-Rate Alerts** | Alert on error budget consumption speed, not raw error counts. This is the Google SRE book approach — it reduces false positives while catching slow-burn issues that threshold alerts miss. |
| **Runbooks** | Step-by-step procedures for each alert. When an engineer is paged at 3 AM, they shouldn't have to think about what to do — the runbook tells them exactly which commands to run, what to check, and when to escalate. |
| **Incident Simulation Scripts** | Python scripts that inject failures (high error rate, latency spike, disk fill) to test whether alerts fire, runbooks work, and the team can recover. Running drills in business hours prevents surprises during real incidents. |
| **Postmortem Template** | Structured blameless postmortem. Documents what happened, why, how it was fixed, and what action items prevent recurrence. Without this structure, the same incidents repeat. |

### Why Each Command Matters

- `python scripts/simulate-incident.py --type high-error-rate` — Injects 5xx errors into the application. This should trigger the SLO burn-rate alert within 5 minutes, page the on-call engineer, and the runbook should lead to resolution.
- `kubectl apply -f prometheus/burn-rate-alerts.yaml` — Loads alert rules that fire based on how fast the error budget is being consumed, not just whether errors exist.
- `kubectl apply -f prometheus/alertmanager-config.yaml` — Configures where alerts go: PagerDuty for critical, Slack for warnings, email for informational.

### Where This Leads

Lab 11 creates manual incident response. Lab 12 automates it — PagerDuty triggers Lambda functions that auto-remediate common issues. Lab 19 (Phase 8) implements the same SLO alerting for the e-commerce platform.

**Key Results:** Structured incident response, error budget visibility, validated recovery procedures

---

## Lab 12: Automated Incident Response & Postmortem Pipeline

### What We're Building

Event-driven incident automation. PagerDuty detects an incident → Lambda function creates a Slack channel, Jira ticket, and looks up the runbook → auto-remediator attempts a fix (restart pod, scale up, clear cache) → if it works, the incident is auto-resolved; if not, it pages a human. After resolution, a postmortem document is auto-generated.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **PagerDuty** | Industry-standard incident management. On-call schedules, escalation policies, and integration with monitoring tools (Prometheus, CloudWatch). PagerDuty decides *who* gets paged based on schedules and severity. |
| **Lambda (Incident Router)** | Serverless function triggered by PagerDuty webhooks. Creates the Slack channel, Jira ticket, and looks up the relevant runbook — all within seconds of an alert firing. Serverless means no server to maintain and it scales to any incident volume. |
| **Lambda (Auto-Remediator)** | Second function that attempts automated fixes for known issues. Has safety limits: only attempts remediation 3 times, only for specific alert types, and always pages a human if the fix doesn't work. |
| **Slack** | War room for incident communication. The auto-created channel ensures all context is in one place, not scattered across DMs and email threads. |
| **Jira** | Tracks action items from postmortems. Without tracking, the same incidents recur because nobody follows through on fixes. |
| **API Gateway** | Receives PagerDuty webhooks and routes them to the correct Lambda function. Provides authentication, rate limiting, and logging. |

### Why Each Command Matters

- `aws lambda create-function --function-name incident-router` — Deploys the routing logic. This function is the brain of the automation — it decides what actions to take based on the incident type and severity.
- `aws apigateway create-rest-api` — Creates the webhook endpoint that PagerDuty calls when an alert fires. Without this, PagerDuty has nowhere to send incident data.
- `aws lambda invoke --function-name auto-remediator --payload '{"type":"pod-crash"}'` — Tests the auto-remediation logic without a real incident. Always test automation before relying on it.

### Where This Leads

Automated incident response reduces MTTR from 45 minutes to 8 minutes. The postmortem pipeline feeds back into Labs 13-14 (chaos engineering) — postmortem action items become chaos experiments to prevent recurrence.

**Key Results:** 82% faster MTTR (45→8 min), 70% fewer repeat incidents, 100% postmortem completion

---

## Lab 13: Chaos Engineering & Resilience Testing (AWS FIS)

### What We're Building

A proactive failure injection program using AWS Fault Injection Simulator. Instead of waiting for production outages to discover weaknesses, we intentionally break things in a controlled way: stop EC2 instances, inject network latency, fill disks, stress CPUs — then measure whether the system recovers automatically.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **AWS FIS** | AWS-native chaos engineering service. Injects failures at the infrastructure level (EC2, EBS, networking) with built-in safety controls — stop conditions automatically abort experiments if impact exceeds thresholds. |
| **Litmus Chaos** | Kubernetes-native chaos for pod-level experiments (kill pods, inject network latency between pods). FIS handles infrastructure; Litmus handles application-level chaos. |
| **Python Orchestrator** | Custom script that runs experiments, collects metrics, and generates reports. Standardizes the process so anyone on the team can run experiments, not just chaos engineering experts. |
| **Prometheus + Grafana** | Measures impact during experiments. If you inject 200ms network latency, what happens to p99 response time? Does the error rate spike? Do circuit breakers activate? Without measurement, chaos engineering is just breaking things. |
| **Stop Conditions** | CloudWatch alarms that abort experiments if error rates exceed safe thresholds. This is the difference between chaos engineering and negligence — there's always a safety net. |

### Why Each Command Matters

- `aws fis create-experiment-template --cli-input-json file://ec2-instance-stop.json` — Defines the experiment: which instances to stop, for how long, and what stop conditions abort it. The template is reusable across multiple runs.
- `aws fis start-experiment --experiment-template-id EXT123` — Runs the experiment. Monitor Grafana dashboards during this — you're watching to see if auto-scaling, health checks, and failover work as designed.
- `python scripts/run-experiment.py --experiment ec2-stop --duration 5m` — Uses the custom orchestrator to run the experiment with standardized pre/post metrics collection.
- `python scripts/analyze-results.py --experiment-id EXP123` — Generates a report: hypothesis, what happened, metrics comparison (before/during/after), and recommendations.

### Where This Leads

Chaos experiments validate the resilience built in Labs 01-07. Discoveries from Lab 13 feed into Lab 14 (Kubernetes-focused chaos). Lab 19 (Phase 10) integrates chaos experiments into quarterly Game Days.

**Key Results:** 12 failure modes discovered, 40% faster recovery, 99.99% availability validated

---

## Lab 14: Chaos Engineering with Litmus Chaos

### What We're Building

Kubernetes-native chaos framework with steady-state hypothesis validation and a resilience scorecard. Each experiment starts with a hypothesis ("if we kill 50% of order-service pods, the API should remain available"), runs the experiment, and validates the hypothesis with probes. The scorecard quantifies each service's resilience score (0-100).

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **LitmusChaos** | Kubernetes-native, so experiments are defined as CRDs (Custom Resource Definitions). `kubectl apply -f pod-delete.yaml` is all it takes to run an experiment. Integrates with the Kubernetes lifecycle. |
| **Steady-State Probes** | HTTP probes that run continuously during the experiment. If the API stops responding, the experiment verdict is "Fail" — the system doesn't meet its resilience requirements. Without probes, you're just breaking things without measuring impact. |
| **Resilience Scorecard** | Aggregates experiment results into a per-service score. "Order Service: 95/100, Payment Service: 65/100" immediately shows where to invest in reliability improvements. |
| **Bash Scripts** | `run-all-experiments.sh` runs the full experiment suite in sequence. `generate-scorecard.sh` parses results and produces the scorecard. Automation ensures experiments are run consistently. |

### Why Each Command Matters

- `kubectl apply -f experiments/pod-delete.yaml` — Creates a ChaosEngine that kills 50% of target pods every 10 seconds for 30 seconds, while continuously probing the health endpoint.
- `kubectl get chaosresult -n production -w` — Watches experiment results in real-time. The verdict is "Pass" (system recovered) or "Fail" (probe detected unavailability).
- `bash scripts/generate-scorecard.sh` — Aggregates all experiment results into a single resilience report with scores per service and improvement recommendations.

### Where This Leads

The resilience scorecard identifies which services need hardening. Low-scoring services get circuit breakers (Lab 07), retry logic, and tighter health probe configurations. Lab 19 (Phase 10) runs these experiments as part of monthly Game Days.

**Key Results:** Resilience scores per service, found missing retry logic and circuit breakers, 12s mean recovery time

---

## Lab 15: Cloud Security & Compliance Framework

### What We're Building

An automated AWS security posture covering threat detection (GuardDuty), compliance rules (AWS Config), audit logging (CloudTrail), encryption (KMS), and centralized findings (Security Hub). Maps to ISO 27001 and SOC 2 controls.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Security Hub** | Centralizes security findings from GuardDuty, Config, and third-party scanners into one dashboard. Without centralization, security issues get lost across separate consoles. |
| **GuardDuty** | Machine learning-based threat detection. Analyzes VPC Flow Logs, CloudTrail, and DNS logs to detect compromised instances, unauthorized access, and data exfiltration. It catches things that rules-based systems miss. |
| **AWS Config** | Evaluates resources against compliance rules. "Are all S3 buckets encrypted?" "Are all security groups restricting SSH?" Config continuously monitors and flags non-compliant resources. |
| **CloudTrail** | Audit trail of every API call in the AWS account. If someone changes a security group or creates an IAM user, CloudTrail records who did it, when, and from where. Required for any compliance certification. |
| **KMS** | Manages encryption keys. All data at rest (S3, RDS, EBS) is encrypted with KMS-managed keys. Key rotation is automatic. |

### Why Each Command Matters

- `terraform apply` — Provisions the entire security stack as code. Security configuration must be version-controlled and reproducible — manual console changes create drift and audit gaps.
- `bash scripts/security-audit.sh` — Runs a comprehensive check: public S3 buckets, open security groups, IAM users without MFA, unencrypted volumes. Outputs a pass/fail report.
- `aws securityhub get-findings --filters '{"SeverityLabel":[{"Value":"CRITICAL"}]}'` — Lists critical findings that need immediate attention.

### Where This Leads

Lab 15 secures the AWS infrastructure. Lab 16 extends security into Kubernetes (RBAC, NetworkPolicies, Vault). Lab 19 (Phase 9) combines both layers for end-to-end security.

**Key Results:** 100% audit pass rate, ISO 27001 + SOC 2 compliance, 45% faster threat detection

---

## Lab 16: Kubernetes Security — RBAC, Network Policies & Vault

### What We're Building

Defense-in-depth security for Kubernetes across 6 layers: access control (RBAC), network segmentation (NetworkPolicies), image scanning (Trivy), runtime detection (Falco), admission policies (OPA/Gatekeeper), and secrets management (Vault).

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **RBAC** | Controls who can do what in the cluster. Developers can view logs but not delete pods. CI/CD can deploy but not access secrets. Least-privilege access prevents accidental and malicious damage. |
| **NetworkPolicies** | Zero-trust networking. By default, every pod can reach every other pod. NetworkPolicies restrict traffic to only the paths that should exist: frontend → backend → database, but not frontend → database directly. |
| **Trivy Operator** | Continuously scans running container images for CVEs. Unlike CI-time scanning (Lab 05), the operator catches vulnerabilities discovered *after* deployment — a new CVE is published, and Trivy immediately flags affected pods. |
| **Falco** | Runtime threat detection. Monitors system calls and flags suspicious behavior: shell spawned inside a container, sensitive file read, unexpected network connection. Catches attacks that bypass static scanning. |
| **OPA/Gatekeeper** | Admission controller that enforces policies. "No container can run as root," "all images must come from our ECR registry," "every pod must have resource limits." Violations are rejected before the pod is created. |
| **HashiCorp Vault** | Dynamic secrets management. Instead of storing database passwords in Kubernetes Secrets (base64-encoded, not encrypted), Vault generates short-lived credentials on demand. If a credential leaks, it expires automatically. |

### Why Each Command Matters

- `kubectl apply -f rbac/namespace-roles.yaml` — Creates roles that limit what each team can do within their namespace. The developer role can `get`, `list`, `watch` pods but cannot `delete` or `exec`.
- `kubectl apply -f network-policies/default-deny.yaml` — Denies all traffic by default. From this point, you must explicitly allow each communication path. This is the foundation of zero-trust.
- `kubectl apply -f scanning/falco-rules.yaml` — Loads runtime detection rules. Falco will alert on shell access, package manager usage, and sensitive file reads inside containers.
- `bash scripts/setup-vault.sh` — Initializes Vault, enables the Kubernetes auth method, and configures dynamic database credential generation.
- `bash scripts/compliance-report.sh` — Generates a full security posture report covering all 6 layers. Used for audit evidence.

### Where This Leads

Lab 16 is the Kubernetes security foundation. Lab 19 (Phase 9) implements the same layers for the e-commerce platform with production-grade Vault HA and OPA policies.

**Key Results:** 6-layer defense-in-depth, zero-trust networking, dynamic secrets, CIS benchmark compliance

---

## Lab 17: Serverless Event-Driven Data Processing Pipeline

### What We're Building

A fully serverless pipeline that processes 1M+ events per day: API Gateway receives events → Lambda validates and queues them → SQS buffers for backpressure → Lambda batch-processes → DynamoDB for real-time access + S3 for long-term archival. Zero servers to manage.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **API Gateway** | Managed HTTP endpoint that handles authentication, rate limiting, and request validation before your code even runs. Scales automatically to any request rate. |
| **Lambda (Ingestion)** | Validates incoming events and publishes to SQS. Lambda scales from zero to thousands of concurrent invocations automatically — you pay only for the compute time used (millisecond billing). |
| **SQS** | Message queue that decouples ingestion from processing. If the processor falls behind, messages wait in the queue instead of being dropped. Dead Letter Queue (DLQ) captures failed messages for investigation — zero data loss. |
| **Lambda (Processor)** | Batch-processes messages from SQS (up to 10 at a time). Writes to DynamoDB for fast queries and S3 for cheap archival. Batching reduces the number of DynamoDB write operations, lowering cost. |
| **DynamoDB** | NoSQL database for real-time event queries. Sub-millisecond read latency, automatic scaling, no connection pooling to manage. Pay per request or provision capacity. |
| **S3** | Long-term event archival at $0.023/GB/month. Events older than 30 days are only needed for compliance and analysis — S3's cost is 100x less than keeping them in DynamoDB. |

### Why Each Command Matters

- `terraform apply` — Provisions the entire pipeline: API Gateway, two Lambda functions, SQS queue with DLQ, DynamoDB table, S3 bucket, IAM roles, CloudWatch alarms. Everything is codified.
- `curl -X POST $API_URL/events -d '{"type":"order","data":{...}}'` — Sends a test event through the pipeline. The event flows through API Gateway → Lambda → SQS → Lambda → DynamoDB + S3.
- `aws sqs get-queue-attributes --queue-url $DLQ_URL --attribute-names ApproximateNumberOfMessagesVisible` — Checks for failed messages in the DLQ. A non-zero count means some events couldn't be processed — investigate immediately.

### Where This Leads

Serverless patterns complement the container-based architecture in other labs. Lab 19 (Phase 2) uses event-driven communication (RabbitMQ) between microservices — the same decoupling pattern, but within Kubernetes.

**Key Results:** 70% cost savings, <100ms latency, zero data loss, automatic scaling to 1M+ events/day

---

## Lab 18: Cloud Cost Optimization (FinOps)

### What We're Building

A comprehensive FinOps framework across four pillars: visibility (where is money going?), governance (budgets and alerts), rightsizing (are instances too big?), and optimization (Spot instances, Savings Plans). Applied to both AWS resources and Kubernetes workloads.

### Why These Tools

| Tool | Why We Use It |
|------|---------------|
| **Cost Explorer + CUR** | Cost and Usage Reports provide the raw data. Cost Explorer visualizes it. Without visibility, cost optimization is guesswork. |
| **AWS Budgets** | Per-team budget alerts. When a team's spending hits 80% of their monthly budget, they get a warning. At 100%, they get an alert with recommended actions. Prevents surprise bills. |
| **Lambda (Rightsizing Analyzer)** | Analyzes CloudWatch CPU/memory metrics and recommends smaller instance types. An m5.xlarge running at 15% CPU should be an m5.large. This typically saves 20-30% per instance. |
| **Spot Instances** | EC2 instances at 60-90% discount. The catch: AWS can reclaim them with 2-minute notice. Mixed instance Auto Scaling Groups run a base of On-Demand (for stability) plus Spot (for savings). |
| **Kubernetes ResourceQuotas** | Limits how much CPU/memory each namespace can consume. Without quotas, a single team can schedule pods that consume the entire cluster, blocking other teams. |
| **LimitRanges** | Sets default resource requests for containers that don't specify them. Without defaults, pods without resource requests are "best effort" and get OOM-killed first under memory pressure. |

### Why Each Command Matters

- `terraform apply -f cost-monitoring/` — Sets up Cost Explorer, anomaly detection, and CUR. From this point, every dollar spent is tracked and categorized.
- `terraform apply -f budget-alerts/` — Creates per-team budgets with SNS alerts. Teams are accountable for their spending.
- `bash scripts/idle-resource-detector.sh` — Finds resources with <5% utilization: unused EBS volumes, idle load balancers, stopped EC2 instances. These are pure waste — delete or downsize them.
- `bash scripts/k8s-cost-report.sh` — Reports Kubernetes cost per namespace and service. "User-service is consuming $450/month, Order-service is $280/month" — this data drives rightsizing decisions.
- `kubectl apply -f policies/resource-quotas.yaml` — Enforces namespace-level limits. The production namespace cannot exceed 40 CPU / 80Gi memory in total.

### Where This Leads

FinOps is the maturity layer. Lab 19 (Phase 13) implements the same concepts with Karpenter (intelligent node provisioning), Kubecost (cost allocation), and Savings Plans.

**Key Results:** 30-60% cost reduction, no surprise bills, automated rightsizing recommendations

---

## Lab 19: E-Commerce Platform — Full DevOps Lifecycle Mastery

### What We're Building

The capstone project. A complete e-commerce platform with 6 microservices, built across 14 phases that cover the *entire* DevOps lifecycle — from `git init` to a self-service internal developer platform. This project ties together every concept from Labs 01-18 into a single, integrated system.

### The 14 Phases (and Why This Order)

| Phase | What You Build | Why This Comes Here |
|-------|---------------|-------------------|
| 1. Foundation | Monorepo + commitlint + Husky | Commit standards drive automated versioning in Phase 5. Can't automate changelogs without structured commits. |
| 2. Microservices | 6 services (Node.js + Python) | The application code that everything else deploys, monitors, and secures. |
| 3. Containerization | Multi-stage Dockerfile + distroless | Containers must be production-ready before pushing to a registry. Distroless eliminates CVEs. |
| 4. Infrastructure | Terraform → VPC + EKS + Aurora | You need somewhere to run the containers. IaC ensures the infrastructure is reproducible. |
| 5. CI/CD | GitHub Actions + Trivy + OIDC | Automates the build-scan-push-deploy cycle. OIDC eliminates static AWS credentials. |
| 6. Kubernetes | Helm + HPA + PDB + probes | Helm charts deploy the services. HPA handles scaling. PDB prevents disruption. Probes enable self-healing. |
| 7. GitOps | ArgoCD + Kustomize | Git becomes the single source of truth. ArgoCD reconciles the cluster with Git continuously. |
| 8. Observability | Prometheus + Grafana + Loki | You can't manage what you can't measure. SLO rules define what "healthy" means. |
| 9. Security | Gatekeeper + Vault + NetworkPolicies | Security must be enforced at admission time (prevent bad deployments), not just detected after the fact. |
| 10. Chaos | Litmus + AWS FIS | Now that we have observability, we can safely inject failures and measure whether the system recovers. |
| 11. Service Mesh | Istio + Flagger canary | mTLS encrypts all inter-service traffic. Flagger enables zero-risk deployments via canary analysis. |
| 12. Multi-Region | Route 53 + Aurora Global + Velero | Disaster recovery for the entire platform. Active-passive with <5 min RTO. |
| 13. FinOps | Karpenter + Kubecost + quotas | The platform is mature — now optimize costs without sacrificing reliability. |
| 14. Platform Eng. | Backstage + Crossplane | Self-service for developers. New service scaffolding in 5 minutes, no tickets needed. |

### Where This Leads

Lab 19 is the culmination. It demonstrates end-to-end ownership of a production system — from writing the first line of code to operating a multi-region, self-healing platform with an internal developer portal.

**Key Results:** 20+ deploys/day, <8 min pipeline, 99.95% SLO, 100% mTLS, 0 critical CVEs, 40% cost savings, <5 min RTO

---

## Kubernetes Learning Path (18 Labs)

### What We're Building

A structured progression from Kubernetes fundamentals to expert-level platform engineering. Four levels map to experience ranges:

| Level | Labs | Experience | What You Learn |
|-------|------|-----------|---------------|
| **Beginner** | K8S-01 to K8S-04 | 0-2 years | Pods, Deployments, Services, Storage, Ingress, Jobs |
| **Intermediate** | K8S-05 to K8S-09 | 2-5 years | StatefulSets, Helm, DaemonSets, Autoscaling, Scheduling |
| **Advanced** | K8S-10 to K8S-14 | 5-10 years | Service Mesh, Multi-Tenancy, Operators, GitOps at Scale, Multi-Cluster |
| **Expert** | K8S-15 to K8S-18 | 10-15+ years | Platform Engineering, Control Plane Internals, DR, Performance/FinOps |

### Why This Progression

Each level builds on the previous one:
- **Beginner** — You can deploy and expose an application. You understand how Kubernetes schedules pods, serves traffic, and stores data.
- **Intermediate** — You can run stateful workloads, manage dependencies with Helm, control resource allocation, and configure auto-scaling.
- **Advanced** — You can secure inter-service communication with Istio, isolate tenants, build custom operators, and manage multiple clusters.
- **Expert** — You can design internal developer platforms, tune the control plane, plan for disaster recovery, and optimize cluster costs.

---

## How to Navigate This Portfolio

**For interviews:** Start with the Key Results tables in each project. They answer "what impact did you deliver?" with specific numbers.

**For learning:** Follow the progression: Labs 01-04 (infrastructure) → Labs 05-07 (CI/CD) → Labs 08-12 (operations) → Labs 13-18 (maturity) → Lab 19 (everything together).

**For specific topics:**
- **CI/CD:** Labs 05, 06, 07, and Lab 19 Phases 5+7
- **Kubernetes:** Labs 05, 08, and the Kubernetes Learning Path
- **Security:** Labs 15, 16, and Lab 19 Phase 9
- **Observability:** Labs 08, 09, 10, 11, and Lab 19 Phase 8
- **Chaos Engineering:** Labs 13, 14, and Lab 19 Phase 10
- **Cost Optimization:** Labs 18 and Lab 19 Phase 13
- **Terraform/IaC:** Labs 01, 02, 03, 04, and Lab 19 Phase 4
